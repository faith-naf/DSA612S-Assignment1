import ballerina/http;
import ballerina/io;
import ballerina/time;

type Status "ACTIVE"|"UNDER_REPAIR"|"DISPOSED";

type Component record {
    string id;
    string name;
    string description?;  
};

type MaintenanceSchedule record {
    string id;
    string scheduleType;
    string lastServiceDate;
    string nextDueDate;
};

type WorkOrder record {
    string id;
    string description;
    string status;
    string createdDate;
};

type Asset record {
    string assetTag;
    string name;
    string faculty;
    string department;
    Status status;
    string acquiredDate;
    Component[] components?;
    MaintenanceSchedule[] schedules?;
    WorkOrder[] workOrders?;
};

//database
map<Asset> assetsDB = {};

service / on new http:Listener(9090) {

    // Create a new asset
    resource function post assets(@http:Payload json payload) returns http:Created|http:BadRequest {
        Asset|error asset = payload.cloneWithType(Asset);
        if asset is error {
            io:println("Error creating asset: ", asset.message());
            return http:BAD_REQUEST;
        }
        
        if assetsDB.hasKey(asset.assetTag) {
            io:println("Asset already exists: ", asset.assetTag);
            return http:BAD_REQUEST;
        }
        
        assetsDB[asset.assetTag] = asset;
        io:println("Asset created: ", asset.assetTag);
        return http:CREATED;
    }

    // view all assets
    resource function get assets() returns json {
        io:println("Getting all assets");
        return <json>assetsDB.toArray();
    }

    // view asset by tag
    resource function get assets/[string assetTag]() returns json|http:NotFound {
        io:println("Getting asset: ", assetTag);
        if !assetsDB.hasKey(assetTag) {
            return http:NOT_FOUND;
        }
        Asset asset = assetsDB[assetTag] ?: {acquiredDate: "", name: "", assetTag: "", department: "", faculty: "", status: "ACTIVE"};
        return <json>asset;
    }

    // Get assets by faculty
    resource function get assets/faculty/[string faculty]() returns Asset[] {
        io:println("Getting assets for faculty: ", faculty);
        Asset[] facultyAssets = [];
        
        foreach var asset in assetsDB.toArray() {
            if asset.faculty == faculty {
                facultyAssets.push(asset);
            }
        }
        
        return facultyAssets;
    }

    // Check for overdue maintenance items
    resource function get assets/maintenance/overdue() returns Asset[] {
        io:println("Checking for overdue maintenance");
        time:Utc currentTime = time:utcNow();
        time:Civil currentDateObj = time:utcToCivil(currentTime);
        string currentDate = string `${currentDateObj.year}-${currentDateObj.month < 10 ? "0" : ""}${currentDateObj.month}-${currentDateObj.day < 10 ? "0" : ""}${currentDateObj.day}`;
        Asset[] overdueAssets = [];
        
        foreach var asset in assetsDB.toArray() {
            if asset.schedules is () {
                continue;
            }
            
            MaintenanceSchedule[] schedules = asset.schedules is MaintenanceSchedule[] ? <MaintenanceSchedule[]>asset.schedules : [];
            foreach var schedule in schedules {
                if schedule.nextDueDate < currentDate {
                    overdueAssets.push(asset);
                    break;
                }
            }
        }
        
        return overdueAssets;
    }

    // Add component to an asset
    resource function post assets/[string assetTag]/components(@http:Payload json payload)
            returns http:Created|http:NotFound|http:BadRequest {
        io:println("Adding component to asset: ", assetTag);
        if !assetsDB.hasKey(assetTag) {
            return http:NOT_FOUND;
        }
        
        Component|error component = payload.cloneWithType(Component);
        if component is error {
            io:println("Error creating component: ", component.message());
            return http:BAD_REQUEST;
        }
        
        Asset asset = assetsDB[assetTag].clone() ?: {acquiredDate: "", name: "", assetTag: "", department: "", faculty: "", status: "ACTIVE"};
        if asset.components is () {
            asset.components = [component];
        } else {
            Component[] existingComponents = asset.components is Component[] ? <Component[]>asset.components : [];
            asset.components = [...existingComponents, component];
        }
        
        assetsDB[assetTag] = asset;
        io:println("Component added to asset: ", assetTag);
        return http:CREATED;
    }

    // Add maintenance schedule to an asset
    resource function post assets/[string assetTag]/schedules(@http:Payload json payload) 
            returns http:Created|http:NotFound|http:BadRequest {
        io:println("Adding schedule to asset: ", assetTag);
        if !assetsDB.hasKey(assetTag) {
            return http:NOT_FOUND;
        }
        
        MaintenanceSchedule|error schedule = payload.cloneWithType(MaintenanceSchedule);
        if schedule is error {
            io:println("Error creating schedule: ", schedule.message());
            return http:BAD_REQUEST;
        }
        
        Asset asset = assetsDB[assetTag].clone() ?: {acquiredDate: "", name: "", assetTag: "", department: "", faculty: "", status: "ACTIVE"};
        if asset.schedules is () {
            asset.schedules = [schedule];
        } else {
            MaintenanceSchedule[] existingSchedules = asset.schedules is MaintenanceSchedule[] ? <MaintenanceSchedule[]>asset.schedules : [];
            asset.schedules = [...existingSchedules, schedule];
        }
        
        assetsDB[assetTag] = asset;
        io:println("Schedule added to asset: ", assetTag);
        return http:CREATED;
    }

    // Update an asset
    resource function put assets/[string assetTag](@http:Payload json payload) 
            returns http:Ok|http:NotFound|http:BadRequest {
        io:println("Updating asset: ", assetTag);
        if !assetsDB.hasKey(assetTag) {
            return http:NOT_FOUND;
        }
        
        Asset|error updatedAsset = payload.cloneWithType(Asset);
        if updatedAsset is error {
            io:println("Error updating asset: ", updatedAsset.message());
            return http:BAD_REQUEST;
        }
        
        assetsDB[assetTag] = updatedAsset;
        io:println("Asset updated: ", assetTag);
        return http:OK;
    }

    // Remove an asset
    resource function delete assets/[string assetTag]() returns http:Ok|http:NotFound {
        io:println("Deleting asset: ", assetTag);
        if !assetsDB.hasKey(assetTag) {
            return http:NOT_FOUND;
        }
        
        _ = assetsDB.remove(assetTag);
        io:println("Asset deleted: ", assetTag);
        return http:OK;
    }

    // Add work order to an asset
    resource function post assets/[string assetTag]/workorders(@http:Payload json payload)
            returns http:Created|http:NotFound|http:BadRequest {
        io:println("Adding work order to asset: ", assetTag);
        if !assetsDB.hasKey(assetTag) {
            return http:NOT_FOUND;
        }
        
        WorkOrder|error workOrder = payload.cloneWithType(WorkOrder);
        if workOrder is error { 
            io:println("Error creating work order: ", workOrder.message());
            return http:BAD_REQUEST;
        }
        
        Asset asset = assetsDB[assetTag].clone() ?: {acquiredDate: "", name: "", assetTag: "", department: "", faculty: "", status: "ACTIVE"};
        if asset.workOrders is () {
            asset.workOrders = [workOrder];
        } else {
            WorkOrder[] existingOrders = asset.workOrders is WorkOrder[] ? asset.workOrders ?: [] : [];
            asset.workOrders = [...existingOrders, workOrder];
        }
        
        assetsDB[assetTag] = asset;
        io:println("Work order added to asset: ", assetTag);
        return http:CREATED;
    }
}
