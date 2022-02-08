// import WebSocket from 'ws';

const WebSocket = require("ws");

const ws = new WebSocket('wss://api-pub.bitfinex.com/ws/2');

ws.on('open', function open() {
  ws.send(JSON.stringify({
    "event" : "subscribe",
    "channel" : "trades",
    "symbol" : "tZECUSD",
  }));
});

ws.on('message', function incoming(message) {
  console.log('received: %s', message);
});