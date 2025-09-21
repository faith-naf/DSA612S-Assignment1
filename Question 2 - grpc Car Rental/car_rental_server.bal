import ballerina/io;
import ballerina/grpc;
import car_rental_pb;

// In-memory data stores
final map<car_rental_pb:Car> cars = {};
final map<car_rental_pb:User> users = {};
final map<string> cart = {}; // user_id -> plate
final map<string> reservations = {}; // user_id -> plate

service class CarRentalService on new grpc:Listener(9090) {

    remote function addCar(car_rental_pb:Car car) returns car_rental_pb:CarResponse|error {
        if cars.hasKey(car.plate) {
            return { plate: car.plate, message: "Car already exists" };
        }
        cars[car.plate] = car;
        return { plate: car.plate, message: "Car added successfully" };
    }

    remote function createUsers(stream<car_rental_pb:User, error?> userStream) returns car_rental_pb:CreateUsersResponse|error {
        error? e = foreach car_rental_pb:User user in userStream {
            users[user.user_id] = user;
        };
        return { message: "Users created successfully" };
    }

    remote function updateCar(car_rental_pb:UpdateCarRequest req) returns car_rental_pb:CarResponse|error {
        if !cars.hasKey(req.plate) {
            return { plate: req.plate, message: "Car not found" };
        }
        car_rental_pb:Car car = cars[req.plate];
        car.daily_price = req.new_daily_price;
        car.status = req.new_status;
        cars[req.plate] = car;
        return { plate: req.plate, message: "Car updated successfully" };
    }

    remote function removeCar(car_rental_pb:RemoveCarRequest req) returns car_rental_pb:CarListResponse|error {
        _ = cars.remove(req.plate);
        return { cars: cars.values().toArray() };
    }

    remote function listAvailableCars(car_rental_pb:CarFilter filter) returns stream<car_rental_pb:Car, error?> {
        stream<car_rental_pb:Car, error?> carStream = new (cars.values().iterator());
        return carStream.filter(function(car_rental_pb:Car car) returns boolean {
            return car.status == "AVAILABLE" && (filter.keyword == "" ||
                car.make.toLowerAscii().includes(filter.keyword.toLowerAscii()) ||
                car.model.toLowerAscii().includes(filter.keyword.toLowerAscii()) ||
                car.year.toString().includes(filter.keyword));
        });
    }

    remote function searchCar(car_rental_pb:SearchCarRequest req) returns car_rental_pb:CarResponse|error {
        if cars.hasKey(req.plate) {
            return { plate: req.plate, message: "Car found" };
        }
        return { plate: req.plate, message: "Car not found" };
    }

    remote function addToCart(car_rental_pb:AddToCartRequest req) returns car_rental_pb:CartResponse|error {
        if !cars.hasKey(req.plate) || cars[req.plate].status != "AVAILABLE" {
            return { message: "Car not available" };
        }
        cart[req.user_id] = req.plate;
        return { message: "Car added to cart" };
    }

    remote function placeReservation(car_rental_pb:PlaceReservationRequest req) returns car_rental_pb:ReservationResponse|error {
        if !cart.hasKey(req.user_id) {
            return { message: "No car in cart", total_price: 0.0 };
        }
        string plate = cart[req.user_id];
        car_rental_pb:Car car = cars[plate];
        // For simplicity, assume 1 day rental
        float totalPrice = car.daily_price;
        reservations[req.user_id] = plate;
        cars[plate].status = "UNAVAILABLE";
        _ = cart.remove(req.user_id);
        return { message: "Reservation placed", total_price: totalPrice };
    }
}

public function main() returns error? {
    check new CarRentalService();
    io:println("Car Rental gRPC server started on port 9090");
}
