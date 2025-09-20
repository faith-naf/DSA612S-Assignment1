import ballerina/log;
import ballerina/grpc;
import ballerina/time;
import ballerina/io;
import ballerina/lang.'string;
import car_rental_pb;

service /CarRentalService on new grpc:Listener(9090) {


    map<car_rental_pb:Car> carDB = {};
    map<string> userRoles = {}; // user_id => role
    map<string> map<car_rental_pb:CartRequest> carts = {}; // user_id => cart items
    map<string> map<string> reservations = {}; // user_id => map<plate => reservation info>

    isolated remote function AddCar(car_rental_pb:Car car) returns car_rental_pb:CarResponse|error {
        if carDB.hasKey(car.plate) {
            return { plate: car.plate, message: "Car already exists" };
        }
        carDB[car.plate] = car;
        return { plate: car.plate, message: "Car added successfully" };
    }

    isolated remote function CreateUsers(stream<car_rental_pb:User> userStream) returns car_rental_pb:UserCreationResponse|error {
        check from car_rental_pb:User user in userStream {
            userRoles[user.user_id] = user.role;
        };
        return { message: "All users created successfully" };
    }

    isolated remote function UpdateCar(car_rental_pb:UpdateCarRequest req) returns car_rental_pb:CarResponse|error {
        if !carDB.hasKey(req.plate) {
            return { plate: req.plate, message: "Car not found" };
        }
        car_rental_pb:Car car = carDB[req.plate];
        car.daily_price = req.new_daily_price;
        car.status = req.new_status;
        carDB[req.plate] = car;
        return { plate: req.plate, message: "Car updated" };
    }

    isolated remote function RemoveCar(car_rental_pb:CarIdentifier id) returns car_rental_pb:CarList|error {
        carDB.remove(id.plate);
        return { cars: carDB.values() };
    }

    isolated remote function ListAvailableCars(car_rental_pb:CarFilter filter) returns stream<car_rental_pb:Car, error?> {
        return new(carDB.values().filter(function(car_rental_pb:Car c) returns boolean {
            return c.status == "AVAILABLE" && 
                (filter.keyword == "" || c.make.toLowerAscii().contains(filter.keyword.toLowerAscii()));
        }));
    }

    isolated remote function SearchCar(car_rental_pb:CarIdentifier id) returns car_rental_pb:CarSearchResponse|error {
        if !carDB.hasKey(id.plate) {
            return { available: false };
        }
        car_rental_pb:Car car = carDB[id.plate];
        return { available: car.status == "AVAILABLE", car: car };
    }

    isolated remote function AddToCart(car_rental_pb:CartRequest req) returns car_rental_pb:CartResponse|error {
        if !carDB.hasKey(req.plate) {
            return { message: "Car not found" };
        }

        
        time:Utc startDate = check time:parse(req.start_date);
        time:Utc endDate = check time:parse(req.end_date);

        if startDate >= endDate {
            return { message: "Invalid dates" };
        }

        map<car_rental_pb:CartRequest> userCart = carts[req.user_id];
        if userCart is () {
            userCart = {};
        }
        userCart[req.plate] = req;
        carts[req.user_id] = userCart;
        return { message: "Car added to cart" };
    }

    isolated remote function PlaceReservation(car_rental_pb:ReservationRequest req) returns car_rental_pb:ReservationResponse|error {
        map<car_rental_pb:CartRequest> cart = carts[req.user_id];
        if cart is () {
            return { message: "No items in cart", total_price: 0.0 };
        }

        float total = 0.0;
        foreach var [_, item] in cart.entries() {
            if !carDB.hasKey(item.plate) || carDB[item.plate].status != "AVAILABLE" {
                return { message: "Car not available: " + item.plate, total_price: 0.0 };
            }

            time:Utc startDate = check time:parse(item.start_date);
            time:Utc endDate = check time:parse(item.end_date);
            int64 days = time:diffDays(startDate, endDate);

            car_rental_pb:Car car = carDB[item.plate];
            total += car.daily_price * <float>days;

            car.status = "UNAVAILABLE"; // Mark as reserved
            carDB[item.plate] = car;
        }

        carts.remove(req.user_id);
        return { message: "Reservation successful", total_price: total };
    }
}
