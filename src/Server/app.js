//process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";

var node_fetch = require('node-fetch');
var CloudKit = require('./cloudkit/cloudkit');
var containerConfig = require('./cloudkit/config');

function println(key, value) {
    console.log("--> " + key + ":");
    console.log(value);
    console.log();
};

function convertToObject(stringObject) {
    return JSON.parse(stringObject.value)
}

function convertToRecord(portfolio) {
    const name = portfolio.recordName;
    const fields = portfolio.fields;
    record = {
        name : name,
        balances : convertToObject(fields.balances),
        asssetGroups : convertToObject(fields.asset_groups),
        targetAllocation : convertToObject(fields.target_allocation),
        rebalanceTrigger : fields.rebalance_trigger.value,
        isLive : fields.isLive != 0,
    }
    return record;
}

CloudKit.configure({
    services: {
        fetch: node_fetch,
        logger: console
    },
    containers: [containerConfig]
});

var container = CloudKit.getDefaultContainer();
var database = container.publicCloudDatabase;

container.setUpAuth()
    .then(function (_) {
        return database.performQuery({ 
            recordType: "Portfolio", 
            filterBy: [{
                comparator: 'EQUALS',
                fieldName: 'is_live',
                fieldValue: { value: 1 },
            }]
        });
    })
    .then(function (response) {
        for (i in response.records) {
            const record = convertToRecord(response.records[i]);
            println("Record", record);
        }
        process.exit()
    });

