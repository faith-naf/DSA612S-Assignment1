import ballerina/http;
import ballerina/log;
import ballerina/io;

http:Client client = check new ("http://localhost:8080");

public function main() returns error? {
    log:printInfo("Starting client demo...");

    // 1) Create an asset
    json asset = {
        assetTag: "EQ-001",
        name: "3D Printer",
        faculty: "Computing & Informatics",
        department: "Software Engineering",
        status: "ACTIVE",
        acquiredDate: "2024-03-10",
        components: [],
        schedules: [],
        workOrders: []
    };
    var res = client->post("/assets", asset);
    if res is http:Response {
        io:println("Create asset status: ", res.statusCode.toString());
        var j = res.getJsonPayload();
        io:println("Created asset response: ", j);
    } else {
        io:println("Error creating asset: ", res);
    }

    // 2) Add a component
    json comp = { name: "Extruder motor", details: "NEMA 17" };
    var compRes = client->post("/assets/EQ-001/components", comp);
    if compRes is http:Response {
        io:println("Add component status: ", compRes.statusCode.toString());
        io:println(compRes.getJsonPayload());
    }

    // 3) Add a schedule
    json sched = { frequency: "yearly", nextDue: "2025-04-01" };
    var schedRes = client->post("/assets/EQ-001/schedules", sched);
    if schedRes is http:Response {
        io:println("Add schedule status: ", schedRes.statusCode.toString());
        io:println(schedRes.getJsonPayload());
    }

    // 4) List all assets
    var all = client->get("/assets");
    if all is http:Response {
        io:println("All assets:", all.getJsonPayload());
    }

    // 5) Query by faculty
    var byFac = client->get("/assets/faculty/Computing & Informatics");
    if byFac is http:Response {
        io:println("By faculty:", byFac.getJsonPayload());
    }

    // 6) Overdue check: provide today param; this returns schedules with nextDue < today
    var ov = client->get("/assets/overdue?today=2025-09-16");
    if ov is http:Response {
        io:println("Overdue assets on 2025-09-16:", ov.getJsonPayload());
    }

    // 7) Update asset (change status)
    asset["status"] = "UNDER_REPAIR";
    var putRes = client->put("/assets/EQ-001", asset);
    if putRes is http:Response {
        io:println("Updated asset:", putRes.getJsonPayload());
    }

    io:println("Client demo finished.");
}
