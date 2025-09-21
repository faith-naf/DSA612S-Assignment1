import ballerina/http;
import ballerina/log;
import ballerina/runtime;

// --- Types ---
type Task record {
    string id;
    string description;
    string status; // e.g., "PENDING", "DONE"
};

type WorkOrder record {
    string id;
    string description;
    string status; // OPEN, IN_PROGRESS, CLOSED
    Task[] tasks;
};

type Component record {
    string id;
    string name;
    string details?;
};

type Schedule record {
    string id;
    string frequency; // e.g., "quarterly", "yearly"
    string nextDue; // "YYYY-MM-DD"
};

type Asset record {
    string assetTag;
    string name;
    string faculty;
    string department;
    string status; // ACTIVE, UNDER_REPAIR, DISPOSED
    string acquiredDate; // "YYYY-MM-DD"
    Component[] components;
    Schedule[] schedules;
    WorkOrder[] workOrders;
};

// --- In-memory DB ---
map<Asset> assetsDB = {};

// simple counters (not persistent)
int componentCounter = 0;
int scheduleCounter = 0;
int workOrderCounter = 0;
int taskCounter = 0;

// --- Helpers ---
function nextComponentId() returns string {
    componentCounter += 1;
    return "C-" + componentCounter.toString();
}
function nextScheduleId() returns string {
    scheduleCounter += 1;
    return "S-" + scheduleCounter.toString();
}
function nextWorkOrderId() returns string {
    workOrderCounter += 1;
    return "WO-" + workOrderCounter.toString();
}
function nextTaskId() returns string {
    taskCounter += 1;
    return "T-" + taskCounter.toString();
}

function ymdToInt(string d) returns int {
    // expects YYYY-MM-DD, return YYYYMMDD as int; on bad format return 0
    if d == "" {
        return 0;
    }
    string cleaned = d.replace("-", "");
    // safe parse
    var maybe = int:fromString(cleaned);
    if maybe is int {
        return maybe;
    }
    return 0;
}
function todayInt() returns int {
    // use runtime:currentTimeMillis -> convert to UTC date string -> build YYYYMMDD
    int ms = runtime:currentTimeMillis();
    // convert to date using epoch math (simple approx using builtin)
    // to avoid using more libs, create Date via new Java interop is not available.
    // We'll construct an ISO date using runtimish approach:
    // Simpler: use environment date via system clock format? If not available, user can supply today's date via query param.
    // For demo, we'll use a crude approach by getting a string from runtime:println? Instead, ask user to rely on server local date.
    // But Ballerina doesn't have direct date formatting here; so for predictable behavior, allow optional query param `today`.
    return 0;
}

// --- Service ---
listener http:Listener ep = new (8080);

service /assets on ep {

    // Create an asset
    resource function post . (http:Caller caller, http:Request req) returns error? {
        var payload = req.getJsonPayload();
        if payload is xml || payload is json {
            Asset asset = <Asset>payload;
            if assetsDB.hasKey(asset.assetTag) {
                check caller->respond({ statusCode: 409, reason: "Asset already exists" });
                return;
            }
            // ensure lists exist
            if asset.components is () {
                asset.components = [];
            }
            if asset.schedules is () {
                asset.schedules = [];
            }
            if asset.workOrders is () {
                asset.workOrders = [];
            }
            assetsDB[asset.assetTag] = asset;
            check caller->respond({ statusCode: 201, reason: "Created", json: asset });
            return;
        } else {
            check caller->respond({ statusCode: 400, reason: "Invalid payload" });
            return;
        }
    }

    // Get all assets
    resource function get . (http:Caller caller) returns error? {
        Asset[] all = [];
        foreach var [k, a] in assetsDB.entries() {
            all.push(a);
        }
        check caller->respond({ statusCode: 200, json: all });
    }

    // Get asset by tag
    resource function get [string tag] (http:Caller caller, string tag) returns error? {
        if !assetsDB.hasKey(tag) {
            check caller->respond({ statusCode: 404, reason: "Not found" });
            return;
        }
        check caller->respond({ statusCode: 200, json: assetsDB[tag] });
    }

    // Update asset
    resource function put [string tag] (http:Caller caller, http:Request req, string tag) returns error? {
        if !assetsDB.hasKey(tag) {
            check caller->respond({ statusCode: 404, reason: "Not found" });
            return;
        }
        var payload = req.getJsonPayload();
        if payload is json {
            Asset updated = <Asset>payload;
            // ensure the tag matches or override
            updated.assetTag = tag;
            // preserve lists if not supplied
            if updated.components is () {
                updated.components = assetsDB[tag].components;
            }
            if updated.schedules is () {
                updated.schedules = assetsDB[tag].schedules;
            }
            if updated.workOrders is () {
                updated.workOrders = assetsDB[tag].workOrders;
            }
            assetsDB[tag] = updated;
            check caller->respond({ statusCode: 200, json: updated });
            return;
        } else {
            check caller->respond({ statusCode: 400, reason: "Invalid payload" });
            return;
        }
    }

    // Delete asset
    resource function delete [string tag] (http:Caller caller, string tag) returns error? {
        if !assetsDB.hasKey(tag) {
            check caller->respond({ statusCode: 404, reason: "Not found" });
            return;
        }
        assetsDB.remove(tag);
        check caller->respond({ statusCode: 200, json: { message: "Deleted", assetTag: tag } });
    }

    // Get assets by faculty
    resource function get faculty [string facultyName] (http:Caller caller, string facultyName) returns error? {
        Asset[] res = [];
        foreach var [k, a] in assetsDB.entries() {
            if a.faculty.toLowerAscii() == facultyName.toLowerAscii() {
                res.push(a);
            }
        }
        check caller->respond({ statusCode: 200, json: res });
    }

    // Get overdue assets: query param optional `today=YYYY-MM-DD` for reproducible testing
    resource function get overdue (http:Caller caller, http:Request req) returns error? {
        string? today = req.getQueryParamValue("today");
        int todayIntVal = 0;
        if today is string {
            todayIntVal = ymdToInt(today);
        } else {
            // fallback: use runtime current millis -> not converted; for demo return 0 => nothing will be overdue unless today provided
            todayIntVal = 0;
        }
        Asset[] res = [];
        foreach var [k, a] in assetsDB.entries() {
            boolean isOverdue = false;
            foreach var s in a.schedules {
                int d = ymdToInt(s.nextDue);
                if d != 0 && todayIntVal != 0 && d < todayIntVal {
                    isOverdue = true;
                    break;
                }
            }
            if isOverdue {
                res.push(a);
            }
        }
        check caller->respond({ statusCode: 200, json: res });
    }

    // --- Components: add component ---
    resource function post ["{tag}", "components"] (http:Caller caller, http:Request req, string tag) returns error? {
        if !assetsDB.hasKey(tag) {
            check caller->respond({ statusCode: 404, reason: "Asset not found" });
            return;
        }
        var payload = req.getJsonPayload();
        if payload is json {
            Component c = <Component>payload;
            c.id = nextComponentId();
            var arr = assetsDB[tag].components;
            arr.push(c);
            Asset a = assetsDB[tag];
            a.components = arr;
            assetsDB[tag] = a;
            check caller->respond({ statusCode: 201, json: c });
            return;
        }
        check caller->respond({ statusCode: 400, reason: "Invalid component" });
    }

    // Delete component
    resource function delete ["{tag}", "components", "{compId}"] (http:Caller caller, string tag, string compId) returns error? {
        if !assetsDB.hasKey(tag) {
            check caller->respond({ statusCode: 404, reason: "Asset not found" });
            return;
        }
        Component[] newComps = [];
        boolean found = false;
        foreach var c in assetsDB[tag].components {
            if c.id == compId {
                found = true;
                continue;
            }
            newComps.push(c);
        }
        if !found {
            check caller->respond({ statusCode: 404, reason: "Component not found" });
            return;
        }
        Asset a = assetsDB[tag];
        a.components = newComps;
        assetsDB[tag] = a;
        check caller->respond({ statusCode: 200, json: { message: "Removed", compId: compId } });
    }

    // --- Schedules: add schedule ---
    resource function post ["{tag}", "schedules"] (http:Caller caller, http:Request req, string tag) returns error? {
        if !assetsDB.hasKey(tag) {
            check caller->respond({ statusCode: 404, reason: "Asset not found" });
            return;
        }
        var payload = req.getJsonPayload();
        if payload is json {
            Schedule s = <Schedule>payload;
            s.id = nextScheduleId();
            var arr = assetsDB[tag].schedules;
            arr.push(s);
            Asset a = assetsDB[tag];
            a.schedules = arr;
            assetsDB[tag] = a;
            check caller->respond({ statusCode: 201, json: s });
            return;
        }
        check caller->respond({ statusCode: 400, reason: "Invalid schedule" });
    }

    // Delete schedule
    resource function delete ["{tag}", "schedules", "{schedId}"] (http:Caller caller, string tag, string schedId) returns error? {
        if !assetsDB.hasKey(tag) {
            check caller->respond({ statusCode: 404, reason: "Asset not found" });
            return;
        }
        Schedule[] newSched = [];
        boolean found = false;
        foreach var s in assetsDB[tag].schedules {
            if s.id == schedId {
                found = true;
                continue;
            }
            newSched.push(s);
        }
        if !found {
            check caller->respond({ statusCode: 404, reason: "Schedule not found" });
            return;
        }
        Asset a = assetsDB[tag];
        a.schedules = newSched;
        assetsDB[tag] = a;
        check caller->respond({ statusCode: 200, json: { message: "Removed", schedId: schedId } });
    }

    // --- Work orders: create new ---
    resource function post ["{tag}", "workorders"] (http:Caller caller, http:Request req, string tag) returns error? {
        if !assetsDB.hasKey(tag) {
            check caller->respond({ statusCode: 404, reason: "Asset not found" });
            return;
        }
        var payload = req.getJsonPayload();
        if payload is json {
            WorkOrder w = <WorkOrder>payload;
            w.id = nextWorkOrderId();
            if w.tasks is () {
                w.tasks = [];
            }
            var arr = assetsDB[tag].workOrders;
            arr.push(w);
            Asset a = assetsDB[tag];
            a.workOrders = arr;
            assetsDB[tag] = a;
            check caller->respond({ statusCode: 201, json: w });
            return;
        }
        check caller->respond({ statusCode: 400, reason: "Invalid workorder" });
    }

    // Update workorder status
    resource function put ["{tag}", "workorders", "{woId}"] (http:Caller caller, http:Request req, string tag, string woId) returns error? {
        if !assetsDB.hasKey(tag) {
            check caller->respond({ statusCode: 404, reason: "Asset not found" });
            return;
        }
        var payload = req.getJsonPayload();
        if payload is json {
            WorkOrder updated = <WorkOrder>payload;
            WorkOrder[] arr = assetsDB[tag].workOrders;
            boolean found = false;
            for int i = 0; i < arr.length(); i += 1 {
                if arr[i].id == woId {
                    updated.id = woId;
                    arr[i] = updated;
                    found = true;
                    break;
                }
            }
            if !found {
                check caller->respond({ statusCode: 404, reason: "WorkOrder not found" });
                return;
            }
            Asset a = assetsDB[tag];
            a.workOrders = arr;
            assetsDB[tag] = a;
            check caller->respond({ statusCode: 200, json: updated });
            return;
        }
        check caller->respond({ statusCode: 400, reason: "Invalid payload" });
    }

    // Add task to workorder
    resource function post ["{tag}", "workorders", "{woId}", "tasks"] (http:Caller caller, http:Request req, string tag, string woId) returns error? {
        if !assetsDB.hasKey(tag) {
            check caller->respond({ statusCode: 404, reason: "Asset not found" });
            return;
        }
        var payload = req.getJsonPayload();
        if payload is json {
            Task t = <Task>payload;
            t.id = nextTaskId();
            WorkOrder[] arr = assetsDB[tag].workOrders;
            boolean found = false;
            for int i = 0; i < arr.length(); i += 1 {
                if arr[i].id == woId {
                    arr[i].tasks.push(t);
                    found = true;
                    break;
                }
            }
            if !found {
                check caller->respond({ statusCode: 404, reason: "WorkOrder not found" });
                return;
            }
            Asset a = assetsDB[tag];
            a.workOrders = arr;
            assetsDB[tag] = a;
            check caller->respond({ statusCode: 201, json: t });
            return;
        }
        check caller->respond({ statusCode: 400, reason: "Invalid task" });
    }

    // Delete task
    resource function delete ["{tag}", "workorders", "{woId}", "tasks", "{taskId}"] (http:Caller caller, string tag, string woId, string taskId) returns error? {
        if !assetsDB.hasKey(tag) {
            check caller->respond({ statusCode: 404, reason: "Asset not found" });
            return;
        }
        WorkOrder[] arr = assetsDB[tag].workOrders;
        boolean foundWO = false;
        boolean foundTask = false;
        for int i = 0; i < arr.length(); i += 1 {
            if arr[i].id == woId {
                foundWO = true;
                Task[] newTasks = [];
                foreach var t in arr[i].tasks {
                    if t.id == taskId {
                        foundTask = true;
                        continue;
                    }
                    newTasks.push(t);
                }
                arr[i].tasks = newTasks;
                break;
            }
        }
        if !foundWO {
            check caller->respond({ statusCode: 404, reason: "WorkOrder not found" });
            return;
        }
        if !foundTask {
            check caller->respond({ statusCode: 404, reason: "Task not found" });
            return;
        }
        Asset a = assetsDB[tag];
        a.workOrders = arr;
        assetsDB[tag] = a;
        check caller->respond({ statusCode: 200, json: { message: "Removed", taskId: taskId } });
    }
} // service end
