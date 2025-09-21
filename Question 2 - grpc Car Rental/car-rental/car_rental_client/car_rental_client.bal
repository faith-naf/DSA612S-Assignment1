import ballerina/io;
import ballerina/grpc;

@grpc:ServiceDescriptor { value: CAR_RENTAL_DESC }


// Create client pointing to server
CarRentalClient endpoint = check new ("http://localhost:9090");

// helper to create a Car object (field names follow generated Ballerina types)
function mkCar(string plate, string make, string model, int year, decimal dailyPrice, int mileage) returns Car {
    return { plate: plate, make: make, model: model, year: year, dailyPrice: <float>dailyPrice, mileage: mileage, status: CarStatus.AVAILABLE };
}

public function main() returns error? {
    // 1) Add a car (admin)
    AddCarResponse addResp = check endpoint->addCar({ car: mkCar("ABC-123", "Toyota", "Corolla", 2020, 40.0, 50000) });
    io:println("AddCar response: ", addResp.message);

    // 2) Stream-create many users (client-streaming)
    // The generated client stub provides a streaming object: check the generated client template for exact names
    var stream = endpoint->createUsers();
    // send 3 users
    check stream->send({ id: "u1", name: "Alice", role: "customer" });
    check stream->send({ id: "u2", name: "Bob", role: "admin" });
    check stream->send({ id: "u3", name: "Carol", role: "customer" });
    // close the stream and get response
    CreateUsersResponse usersResp = check stream->complete();
    io:println("Created users: ", usersResp.created_count.toString());

    // 3) List available cars (server-stream)
    var carStream = endpoint->listAvailableCars({ filter: "" });
    // read responses until done
    io:println("Available cars:");
    var res = carStream.read();
    while res is Car {
        io:println(" - ", res.plate, " ", res.make, " ", res.model, " (", res.year.toString(), ")");
        res = carStream.read();
    }

    // 4) Customer adds to cart then place reservation
    var addCartResp = check endpoint->addToCart({ user_id: "u1", plate: "ABC-123", start_date: "2025-09-25", end_date: "2025-09-27" });
    io:println("AddToCart:", addCartResp.message);

    var reserveResp = check endpoint->placeReservation({ user_id: "u1" });
    io:println("PlaceReservation:", reserveResp.message);
    if reserveResp.ok {
        io:println("Reservation ID:", reserveResp.reservation.reservation_id);
        io:println("Total:", reserveResp.reservation.total_price.toString());
    }
}

