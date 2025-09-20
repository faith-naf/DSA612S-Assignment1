import ballerina/grpc;
import ballerina/time;

type Car record {
    string plate;
    string make;
    string model;
    int year;
    float dailyPrice;
    float mileage;
    string status;
};

type User record {
    string userId;
    string name;
    int role; // 0=Customer, 1=Admin
};

type RentalItem record {
    Car car;
    time:ReadableDate startDate;
    time:ReadableDate endDate;
    float price;
};

type Reservation record {
    string reservationId;
    string userId;
    RentalItem[] items;
    float totalPrice;
    time:ReadableDate reservationDate;
};

map<Car> cars = {};
map<User> users = {};
map<string, RentalItem[]> userCarts = {}; // userId -> list of rental items
map<string, Reservation> reservations = {};

service / on new grpc:Listener(9090) {

    resource function create_users(stream<CreateUserRequest> reqs) returns CreateUserResponse {
        foreach var req in reqs {
            User user = req.user;
            users[user.userId] = user;
        }
        return { message: "Users created successfully" };
    }

    resource function add_car(AddCarRequest req) returns AddCarResponse {
        Car car = req.car;
        cars[car.plate] = car;
        return { carId: car.plate };
    }

    resource function update_car(UpdateCarRequest req) returns UpdateCarResponse {
        string plate = req.plate;
        if (cars.hasKey(plate)) {
            Car updated = req.updatedCar;
            cars[plate] = updated;
            return { message: "Car updated successfully" };
        } else {
            return { message: "Car not found" };
        }
    }

    resource function remove_car(RemoveCarRequest req) returns RemoveCarResponse {
        string plate = req.plate;
        if (cars.hasKey(plate)) {
            cars.remove(plate);
        }
        // Return current list
        return { cars: cars.values() };
    }

    resource function list_available_cars(ListAvailableCarsRequest req) returns stream<CarStream> {
        foreach var car in cars.values() {
            if (car.status == "AVAILABLE") {
                emit { car: car };
            }
        }
    }

    resource function search_car(SearchCarRequest req) returns SearchCarResponse {
        string plate = req.plate;
        if (cars.hasKey(plate)) {
            return { car: cars[plate], found: true };
        } else {
            return { car: null, found: false };
        }
    }

    resource function add_to_cart(AddToCartRequest req) returns AddToCartResponse {
        string userId = req.userId;
        if (!users.hasKey(userId)) {
            return { message: "User not found" };
        }
        if (!cars.hasKey(req.plate)) {
            return { message: "Car not found" };
        }

        Car car = cars[req.plate];

        // Basic date validation
        time:ReadableDate startDate = check time:fromString(req.period.startDate);
        time:ReadableDate endDate = check time:fromString(req.period.endDate);
        if (startDate > endDate) {
            return { message: "Invalid date range" };
        }

        // Check if car is available (simplified)
        if (car.status != "AVAILABLE") {
            return { message: "Car not available" };
        }

        // Add to user's cart
        RentalItem item = {
            car: car,
            startDate: startDate,
            endDate: endDate,
            price: car.dailyPrice * (float)time:dateDiff(startDate, endDate) + 1
        };

        if (!userCarts.hasKey(userId)) {
            userCarts[userId] = [];
        }
        userCarts[userId].push(item);
        return { message: "Car added to cart" };
    }

    resource function place_reservation(PlaceReservationRequest req) returns PlaceReservationResponse {
        string userId = req.userId;
        if (!users.hasKey(userId)) {
            return { message: "User not found" };
        }
        if (!userCarts.hasKey(userId)) {
            return { message: "Cart is empty" };
        }
        RentalItem[] items = userCarts[userId];

        float totalPrice = 0.0;
        list<RentalItem> confirmedItems = [];

        foreach var item in items {
            // Check if car is still available for the dates
            // For simplicity, assume always available
            float days = (float)time:dateDiff(item.startDate, item.endDate) + 1;
            float price = item.car.dailyPrice * days;
            totalPrice += price;
            confirmedItems.push(item);
            // Optionally, change status or reserve logic
        }

        string reservationId = "RES-" + userId + "-" + time:currentTime().toString();
        Reservation reservation = {
            reservationId: reservationId,
            userId: userId,
            items: confirmedItems.toArray(),
            totalPrice: totalPrice,
            reservationDate: time:currentTime()
        };

        reservations[reservationId] = reservation;
        // Clear cart
        userCarts.remove(userId);

        return { message: "Reservation confirmed", reservation: reservation };
    }
}