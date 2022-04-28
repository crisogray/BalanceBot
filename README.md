# BalanceBot
## Cross-exchange Cryptoasset Portfolio Rebalancing
### Building the app
Requirements:
	* Mac computer with Xcode installed
	* iOS device with cable to connect to Mac
	* Apple account enrolled in Apple Developer Program
	* Account on at least one supported exchange (Bitfinex, Kraken, Coinbase, FTX)

1. Connect iOS device to Mac via cable
2. Sign into the developer account in Xcode
3. Open the `src/BalanceBot/BalanceBot.xcodeproj` Xcode project.
4. Select the connected device as the deployment target
5. Build and run the BalanceBot application

### Running the server script
Requirements:
	* NodeJS and NPM are installed
	* App is installed on device
		* Portfolio preferences have been inputted, rebalance trigger is threshold
		* ‘Receive Notifications’ toggle is active
		* Portfolio is outside of threshold

Open the notification NodeJS server script location `src/server/` in terminal.

Run `node app.js` command in terminal