import ballerina/grpc;
import ballerina/io;

function main() returns error {
    grpc:Client client = check new ("http://localhost:9090");

    // 1. Create users
    stream<CreateUserRequest> userStream = [
        { user: { userId: "u1", name: "Alice", role: 0 } },
        { user: { userId: "u2", name: "Bob", role: 1 } }
    ];
    check client->create_users(userStream);
    io:println("Created users.");

    // 2. Add cars (admin)
    Car car1 = {
        plate: "ABC123",
        make: "Toyota",
        model: "Camry",
        year: 2020,
        dailyPrice: 50.0,
        mileage: 30000.0,
        status: "AVAILABLE"
    };
    check client->add_car({ car: car1 });
    io:println("Added car ABC123.");

    // 3. List available cars
    stream<CarStream> cars = check client->list_available_cars({ filter: "" });
    io:println("Available cars:");
    foreach var c in cars {
        io:println(c.car);
    }

    // 4. Customer adds car to cart
    check client->add_to_cart({ userId: "u1", plate: "ABC123", period: { startDate: "2024-09-01", endDate: "2024-09-05" } });
    io:println("Added car to cart.");

    // 5. Place reservation
    check client->place_reservation({ userId: "u1" });
    io:println("Reservation placed.");
}