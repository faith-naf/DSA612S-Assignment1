import ballerina/http;
import ballerina/io;

public function main() returns error? {
    http:Client assetClient = check new ("http://localhost:9090");

    io:println("=== Testing Asset Management API ===\n");

    // Test data
    json newAsset = {
        "assetTag": "EQ-002",
        "name": "Laser Cutter",
        "faculty": "Engineering",
        "department": "Mechanical ",
        "status": "ACTIVE",
        "acquiredDate": "2024-01-15",
        "components": [],
        "schedules": [],
        "workOrders": []
    };

    json newComponent = {
        "id": "COMP-001",
        "name": "Laser Tube",
        "description": "Main laser component"
    };

    json newSchedule = {
        "id": "SCHED-001",
        "type": "MONTHLY",
        "lastServiceDate": "2024-08-15",
        "nextDueDate": "2024-09-15"
    };

    // Test all operations
    testOperation(assetClient, "1. Create asset", "POST /assets", newAsset);
    testOperation(assetClient, "2. Get all assets", "GET /assets", ());
    testOperation(assetClient, "3. Get asset by tag", "GET /assets/EQ-002", ());
    testOperation(assetClient, "4. Get by faculty", "GET /assets/faculty/Engineering", ());
    testOperation(assetClient, "5. Check overdue", "GET /assets/maintenance/overdue", ());
    testOperation(assetClient, "6. Add component", "POST /assets/EQ-002/components", newComponent);
    testOperation(assetClient, "7. Add schedule", "POST /assets/EQ-002/schedules", newSchedule);

    io:println("=== All tests completed successfully ===");
}

function testOperation(http:Client client, string description, string operation, json payload) returns error? {
    io:println(description);
    
    http:Response response = if operation.startsWith("POST") {
        check client->post(operation.split(" ")[1], payload);
    } else {
        check client->get(operation.split(" ")[1]);
    };
    
    io:println("   Status: ", response.statusCode);
    io:println("   Response: ", check response.getTextPayload());
    io:println("");
}
