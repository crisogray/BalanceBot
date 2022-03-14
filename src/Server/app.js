//process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";

var node_fetch = require('node-fetch');

var CloudKit = require('./cloudkit/cloudkit');
var containerConfig = require('./cloudkit/config');

const CoinGecko = require('coingecko-api');
const CoinGeckoClient = new CoinGecko();

function println(key, value) {
    console.log("--> " + key + ":");
    console.log(value);
    console.log();
};

async function livePortfolios() {
    let response = await database.performQuery({ 
        recordType: "Portfolio", 
        filterBy: [{
            comparator: 'EQUALS',
            fieldName: 'is_live',
            fieldValue: { value: 1 },
        }]
    });
    return response.records.map(r => convertToRecord(r));
}

function convertToObject(stringObject) {
    return JSON.parse(stringObject.value)
}

function convertToRecord(record) {
    const name = record.recordName;
    const fields = record.fields;
    return { 
        name : name,
        balances : convertToObject(fields.balances),
        assetGroups : convertToObject(fields.asset_groups),
        targetAllocation : convertToObject(fields.target_allocation),
        rebalanceTrigger : fields.rebalance_trigger.value,
        isLive : fields.isLive != 0,
    };
}

function addingUnique(newValues, existing) {
    var working = existing;
    for (i in newValues) {
        const value = newValues[i];
        if (!working.includes(value)) {
            working.push(value)
        }
    } 
    return working
}

function tickersNeeded(portfolio) {
    var balances = Object.keys(portfolio.balances);
    var targetTickers = Object.keys(portfolio.targetAllocation);
    for (i in targetTickers) {
        const ticker = targetTickers[i];
        var tickers = [ticker]
        if (ticker in portfolio.assetGroups) 
            tickers = portfolio.assetGroups[ticker];
        balances = addingUnique(tickers, balances)
    }
    const usdIndex = balances.indexOf("USD")
    if (usdIndex >= 0) balances.splice(usdIndex, 1);
    return balances
}

function aggregateTickers(records) {
    var tickers = []
    records.forEach(element => { 
        tickers = addingUnique(tickersNeeded(element), tickers)
    });
    return tickers
}

async function idsForSymbols(tickers) {
    let data = await CoinGeckoClient.coins.list()
    let currencies = data.data.filter(function (obj) {
        return tickers.includes(obj.symbol.toUpperCase());
    });
    let symbolIds = {}
    currencies.forEach(function (currency) { 
        const symbol = currency.symbol.toUpperCase()
        const currentId = symbolIds[symbol]
        if (currentId && currency.id.length > currentId.length) 
            return;
        symbolIds[symbol] = currency.id
    });
    return symbolIds
}

async function getPrices(tickers) {
    const symbolIds = await idsForSymbols(tickers);
    const symbols = Object.values(symbolIds).join(",");
    let prices = await CoinGeckoClient.simple.price({
        ids: symbols, vs_currencies: "usd"
    });
    var symbolPrices = {USD : 1};
    tickers.forEach(ticker => {
        symbolPrices[ticker] = prices.data[symbolIds[ticker]].usd;
    });
    return symbolPrices
}

function isCalendar(rebalanceTrigger) {
    return rebalanceTrigger.includes("calendar");
}

function threshold(rebalanceTrigger) {
    return parseInt(schedule(rebalanceTrigger))
}

function schedule(rebalanceTrigger) {
    return rebalanceTrigger.split(":")[1]
}

function groupBalances(balances, assetGroups) {
    let groupedBalances = balances;
    Object.keys(assetGroups).forEach(groupName => {
        var total = 0.0;
        assetGroups[groupName].forEach(ticker => {
            total += groupedBalances[ticker];
            delete groupedBalances[ticker];
        });
        groupedBalances[groupName] = total;
    });
    return groupedBalances
}

function balancesToPercentages(balances) {
    const total = Object.values(balances).reduce((a, b) => a + b, 0);
    let percentages = {};
    Object.keys(balances).map(ticker => {
        percentages[ticker] = 100 * balances[ticker] / total
    });
    return percentages;
}

function currentAllocation(portfolio, prices) {
    let usdBalances = {};
    Object.keys(portfolio.balances).forEach(ticker => {
        usdBalances[ticker] = portfolio.balances[ticker] * prices[ticker];
    });
    let assetGroups = {};
    Object.keys(portfolio.assetGroups).forEach(groupName => {
        if (groupName in portfolio.targetAllocation) {
            assetGroups[groupName] = portfolio.assetGroups[groupName]
        }
    });
    let groupedBalances = groupBalances(usdBalances, assetGroups);
    Object.keys(portfolio.targetAllocation).filter(x => {
        return !Object.keys(groupedBalances).includes(x)
    }).forEach(ticker => groupedBalances[ticker] = 0);
    return balancesToPercentages(groupedBalances);
}

function needsRebalance(portfolio, prices) {
    const allocation = currentAllocation(portfolio, prices); 
    const t = threshold(portfolio.rebalanceTrigger);
    const diffs = Object.keys(portfolio.targetAllocation).map(ticker => {
        return Math.abs(allocation[ticker] - portfolio.targetAllocation[ticker]) >= t
    });
    return diffs.includes(true);
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

async function calculateRebalances() {
    await container.setUpAuth()
    const records = await livePortfolios()
    const tickers = aggregateTickers(records);
    const prices = await getPrices(tickers);
    records.forEach(record => {
        if (needsRebalance(record, prices)) {
            println("Needs Rebalance", record.name)
        }
    });
    process.exit()
}

calculateRebalances()



