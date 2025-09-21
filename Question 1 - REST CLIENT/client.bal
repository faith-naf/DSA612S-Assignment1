import ballerina/http;
import ballerina/io;

public function main() returns error? {
    http:Client assetClient = check new ("http://localhost:9090");

    io:println("Test Asset Management API \n");

    // JSON object to test data 
    json newAsset = {
        "assetTag": "EQ-002",
        "name": "Laser Cutter",
        "faculty": "Software Engineering",
        "department": "Mechanical",
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
        "scheduleType": "MONTHLY",
        "lastServiceDate": "2024-08-15",
        "nextDueDate": "2024-09-15"
    };

    // JSON object to update
    json updatedAsset = {
        "assetTag": "EQ-002",
        "name": "Laser Cutter - Updated",
        "faculty": "Software Engineering",
        "department": "Mechanical",
        "status": "UNDER_REPAIR",
        "acquiredDate": "2024-01-15",
        "components": [],
        "schedules": [],
        "workOrders": []
    };

    // Testing service operations
    check testOperation(assetClient, "1. Create asset", "POST /assets", newAsset);
    check testOperation(assetClient, "2. Get all assets", "GET /assets", ());
    check testOperation(assetClient, "3. Get asset by tag", "GET /assets/EQ-002", ());
    check testOperation(assetClient, "4. Get by faculty", "GET /assets/faculty/Software Engineering", ());
    check testOperation(assetClient, "5. Check overdue", "GET /assets/maintenance/overdue", ());
    check testOperation(assetClient, "6. Add component", "POST /assets/EQ-002/components", newComponent);
    check testOperation(assetClient, "7. Add schedule", "POST /assets/EQ-002/schedules", newSchedule);
    check testOperation(assetClient, "8. Update asset", "PUT /assets/EQ-002", updatedAsset);

    io:println("All tests completed successfully");
}

function testOperation(http:Client client, string description, string operation, json payload) returns error? {
    io:println(description);

    string method = operation.split(" ")[0];
    string path = operation.split(" ")[1];

    http:Response response = if method == "POST" {
        check client->post(path, payload);
    } else if method == "PUT" {
        check client->put(path, payload);
    } else if method == "DELETE" {
        check client->delete(path);
    } else {
        check client->get(path);
    };

    io:println("Status: ", response.statusCode.toString());
    io:println("Response: ", check response.getTextPayload());
    io:println("");
}
