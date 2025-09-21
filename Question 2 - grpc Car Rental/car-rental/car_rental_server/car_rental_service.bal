import ballerina/log;
import ballerina/time;
import ballerina/grpc;
import car_rental_server.car_rental_pb;

listener grpc:Listener carListener = new(9090);

@grpc:Descriptor { value: car_rental_pb.CAR_RENTAL_DESC }
service "CarRental" on carListener {

    remote function addCar(car_rental_pb:AddCarRequest req) returns car_rental_pb:AddCarResponse|error {
        car_rental_pb:Car c = req.car;
        if c.plate == "" {
            return { plate: "", ok: false, message: "Missing plate" };
        }
        if cars.hasKey(c.plate) {
            return { plate: c.plate, ok: false, message: "Car already exists" };
        }
        cars[c.plate] = c;
        log:printInfo("Car added: " + c.plate);
        return { plate: c.plate, ok: true, message: "Car added" };
    }

    remote function createUsers(stream<car_rental_pb:CreateUser , error?> userStream) returns car_rental_pb:CreateUsersResponse|error {
        int created = 0;
        var next = userStream.read();
        while next is car_rental_pb:CreateUser  {
            car_rental_pb:CreateUser  u = next;
            users[u.id] = u;
            created += 1;
            next = userStream.read();
        }
        log:printInfo("Users created: " + created.toString());
        return { createdCount: created };
    }

    remote function updateCar(car_rental_pb:UpdateCarRequest req) returns car_rental_pb:UpdateCarResponse|error {
        string plate = req.plate;
        if !cars.hasKey(plate) {
            return { ok: false, message: "Car not found" };
        }
        car_rental_pb:Car updated = req.car;
        updated.plate = plate;
        cars[plate] = updated;
        log:printInfo("Car updated: " + plate);
        return { ok: true, message: "Car updated" };
    }

    remote function removeCar(car_rental_pb:RemoveCarRequest req) returns car_rental_pb:ListCarsResponse|error {
        string plate = req.plate;
        if cars.hasKey(plate) {
            cars.remove(plate);
            log:printInfo("Car removed: " + plate);
        }
        car_rental_pb:Car[] arr = [];
        foreach var [_, v] in cars.entries() {
            arr.push(v);
        }
        return { cars: arr };
    }

    remote function listAvailableCars(car_rental_pb:ListAvailableCarsRequest req) returns stream<car_rental_pb:Car, error?>|error {
        stream<car_rental_pb:Car, error?> outStream = new;
        string filter = req.filter;
        foreach var [_, c] in cars.entries() {
            if c.status == car_rental_pb:CarStatus.AVAILABLE {
                boolean matches = (filter == "" || filter == nil) ||
                                  (c.make.toLowerAscii().contains(filter.toLowerAscii())) ||
                                  (c.model.toLowerAscii().contains(filter.toLowerAscii())) ||
                                  (c.year.toString().contains(filter));
                if matches {
                    outStream.publish(c);
                }
            }
        }
        outStream.complete();
        return outStream;
    }

    remote function searchCar(car_rental_pb:SearchCarRequest req) returns car_rental_pb:SearchCarResponse|error {
        string plate = req.plate;
        if !cars.hasKey(plate) {
            return { available: false, message: "Car not found" };
        }
        car_rental_pb:Car c = cars[plate];
        if c.status == car_rental_pb:CarStatus.AVAILABLE {
            return { car: c, available: true, message: "Available" };
        } else {
            return { car: c, available: false, message: "Not available" };
        }
    }

    remote function addToCart(car_rental_pb:AddToCartRequest req) returns car_rental_pb:AddToCartResponse|error {
        string uid = req.userId;
        string plate = req.plate;
        if !cars.hasKey(plate) {
            return { ok: false, message: "Car not found" };
        }
        car_rental_pb:Car c = cars[plate];
        if c.status != car_rental_pb:CarStatus.AVAILABLE {
            return { ok: false, message: "Car not available" };
        }
        int days = daysBetween(req.startDate, req.endDate);
        if days <= 0 {
            return { ok: false, message: "Invalid dates" };
        }
        double price = <double>days * c.dailyPrice;
        if !carts.hasKey(uid) {
            carts[uid] = { userId: uid, items: [] };
        }
        Cart cart = carts[uid];
        cart.items.push({ plate: plate, startDate: req.startDate, endDate: req.endDate, price: price });
        carts[uid] = cart;
        log:printInfo("Added to cart: " + plate + " for user " + uid);
        return { ok: true, message: "Added to cart" };
    }

    remote function placeReservation(car_rental_pb:PlaceReservationRequest req) returns car_rental_pb:PlaceReservationResponse|error {
        string uid = req.userId;
        if !carts.hasKey(uid) {
            return { ok: false, message: "Cart empty" };
        }
        Cart cart = carts[uid];
        double total = 0.0;
        car_rental_pb:CarItem[] items = [];
        foreach var item in cart.items {
            if !cars.hasKey(item.plate) {
                return { ok: false, message: "Car disappeared: " + item.plate };
            }
            car_rental_pb:Car c = cars[item.plate];
            if c.status != car_rental_pb:CarStatus.AVAILABLE {
                return { ok: false, message: "Car not available: " + item.plate };
            }
            // reserve
            c.status = car_rental_pb:CarStatus.UNAVAILABLE;
            cars[item.plate] = c;
            total += item.price;
            car_rental_pb:CarItem pbItem = {
                plate: item.plate,
                startDate: item.startDate,
                endDate: item.endDate,
                price: item.price
            };
            items.push(pbItem);
        }
        string resId = "RES-" + time:currentTime().epoch.toString();
        car_rental_pb:Reservation res = {
            reservationId: resId,
            userId: uid,
            items: items,
            totalPrice: total,
            placedAt: time:currentTime().epoch.toString()
        };
        reservations[resId] = res;
        carts.remove(uid);
        log:printInfo("Reservation placed: " + resId + " for user " + uid);
        return { ok: true, reservation: res, message: "Reservation placed" };
    }
}

// ---------- In-memory storage ----------
map<car_rental_pb:Car> cars = {};
map<car_rental_pb:CreateUser > users = {};
map<Cart> carts = {};
map<car_rental_pb:Reservation> reservations = {};

// Local helper records (use camelCase here)
type CartItem record {
    string plate;
    string startDate;
    string endDate;
    double price;
};

type Cart record {
    string userId;
    CartItem[] items = [];
};

// Utility: date difference (days) for ISO yyyy-mm-dd strings
function daysBetween(string startDate, string endDate) returns int {
    var s = time:parse(startDate, "yyyy-MM-dd");
    var e = time:parse(endDate, "yyyy-MM-dd");
    if s is time:Civil && e is time:Civil {
        int diffDays = <int> time:diff(e, s).days;
        if diffDays <= 0 {
            return 0;
        }
        return diffDays;
    }
    return 0;
}