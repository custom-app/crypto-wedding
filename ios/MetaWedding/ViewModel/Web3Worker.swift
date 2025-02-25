//
//  Web3.swift
//  MetaWedding
//
//  Created by Лев Бакланов on 04.04.2022.
//

import Foundation
import web3swift
import BigInt

class Web3Worker: ObservableObject {
    
    let zeroAddress = "0x0000000000000000000000000000000000000000"
    
    private let web3: web3
    private let weddingContract: EthereumContract
    private let weddingContractWeb3: web3.web3contract
    private let faucetContract: EthereumContract
    private let faucetContractWeb3: web3.web3contract
    
    private let web3Agent: web3
    private let weddingContractAgent: web3.web3contract
    
    init(endpoint: String) {
        let chainId = BigUInt(Config.TESTING ? Constants.ChainId.PolygonTestnet : Constants.ChainId.Polygon)
        web3 = web3swift.web3(provider: Web3HttpProvider(URL(string: endpoint)!,
                                                         network: Networks.Custom(networkID: chainId))!)
        let weddingPath = Bundle.main.path(forResource: "wedding_abi", ofType: "json")!
        let faucetPath = Bundle.main.path(forResource: "faucet_abi", ofType: "json")!
        
        let weddingAbi = try! String(contentsOfFile: weddingPath)
        let faucetAbi = try! String(contentsOfFile: faucetPath)
        
        weddingContract = EthereumContract(weddingAbi)!
        faucetContract = EthereumContract(faucetAbi)!
        
        let weddingAddress = Config.TESTING ? Constants.WeddingContract.Testnet : Constants.WeddingContract.Mainnet
        let faucetAddress = Config.TESTING ? Constants.FaucetContract.Testnet : Constants.FaucetContract.Mainnet
        
        weddingContractWeb3 = web3.contract(weddingAbi, at: EthereumAddress(weddingAddress)!, abiVersion: 2)!
        faucetContractWeb3 = web3.contract(faucetAbi, at: EthereumAddress(faucetAddress)!, abiVersion: 2)!
        
        let keystore = try! EthereumKeystoreV3(privateKey: Data.fromHex(Config.faucetK())!)!
        web3.addKeystoreManager(KeystoreManager([keystore]))
        
        web3Agent = web3swift.web3(provider: Web3HttpProvider(URL(string: endpoint)!,
                                                         network: Networks.Custom(networkID: chainId))!)
        let keystoreAgent = try! EthereumKeystoreV3(privateKey: Data.fromHex(Config.agentKey)!)!
        web3Agent.addKeystoreManager(KeystoreManager([keystore]))
        weddingContractAgent = web3Agent.contract(weddingAbi, at: EthereumAddress(weddingAddress)!, abiVersion: 2)!
    }
    
    func getBalance(address: String, onResult: @escaping (Double, Error?) -> ()) {
        if let walletAddress = EthereumAddress(address) {
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                do {
                    let balanceResult = try web3.eth.getBalance(address: walletAddress)
                    let balanceString = Web3.Utils.formatToEthereumUnits(balanceResult, toUnits: .eth, decimals: 6)!
                    print("Balance: \(balanceString)")
                    DispatchQueue.main.async {
                        if let balance = Double(balanceString) {
                            onResult(balance, nil)
                        } else {
                            onResult(0, InnerError.balanceParseError)
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        onResult(0, error)
                    }
                }
            }
        } else {
            onResult(0, InnerError.invalidAddress(address: address))
        }
    }
    
    func callFaucet(to: String, onResult: @escaping (Error?) -> ()) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                let faucetAccount = EthereumAddress(
                    Config.TESTING ? Constants.FaucetAccount.Testnet : Constants.FaucetAccount.Mainnet
                )!
                let parameters: [AnyObject] = [EthereumAddress(to)! as AnyObject]
                var options = TransactionOptions.defaultOptions
                options.value = Web3.Utils.parseToBigUInt("0.0", units: .eth)
                options.from = faucetAccount
                options.gasPrice = .automatic
                options.gasLimit = .automatic
                print("calling faucet")
                let tx = faucetContractWeb3.write(
                    "faucet",
                    parameters: parameters,
                    extraData: Data(),
                    transactionOptions: options)!
                let res = try tx.send()
//                print("got faucet res: \(res)")
            } catch {
                DispatchQueue.main.async {
                    onResult(error)
                }
            }
        }
    }
    
    func getBlockHash(blockId: BigUInt, onResult: @escaping (String, Error?) -> ()) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                let result = try web3.eth.getBlockByNumber(blockId)
                let hash = "0x\(result.hash.toHexString())"
                print("got block hash: \(hash)")
                DispatchQueue.main.async {
                    onResult("0x\(result.hash.toHexString())", nil)
                }
            } catch {
                DispatchQueue.main.async {
                    onResult("", error)
                }
            }
        }
    }
    
    func getGasPrice(onResult: @escaping (BigUInt, Error?) -> ()) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                let estimateGasPrice = try web3.eth.getGasPrice()
                print("Gas price: \(estimateGasPrice)")
                DispatchQueue.main.async {
                    onResult(estimateGasPrice, nil)
                }
            } catch {
                DispatchQueue.main.async {
                    onResult(0, error)
                }
            }
        }
    }
    
    func getIncomingPropositions(address: String, onResult: @escaping ([Proposal], Error?) -> ()) {
        if let walletAddress = EthereumAddress(address) {
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                do {
                    let (proposals, error) = try requestPropositions(address: walletAddress,
                                                                     method: "getIncomingPropositions")
                    DispatchQueue.main.async {
                        onResult(proposals, error)
                    }
                } catch {
                    DispatchQueue.main.async {
                        onResult([], error)
                    }
                }
            }
        } else {
            onResult([], InnerError.invalidAddress(address: address))
        }
    }
    
    func getOutgoingPropositions(address: String, onResult: @escaping ([Proposal], Error?) -> ()) {
        if let walletAddress = EthereumAddress(address) {
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                do {
                    let (proposals, error) = try requestPropositions(address: walletAddress,
                                                                     method: "getOutgoingPropositions")
                    DispatchQueue.main.async {
                        onResult(proposals, error)
                    }
                } catch {
                    DispatchQueue.main.async {
                        onResult([], error)
                    }
                }
            }
        } else {
            onResult([], InnerError.invalidAddress(address: address))
        }
    }
    
    private func requestPropositions(address: EthereumAddress, method: String) throws -> ([Proposal], Error?) {
        var options = TransactionOptions.defaultOptions
        options.from = address
        options.gasPrice = .automatic
        options.gasLimit = .automatic
        let tx = weddingContractWeb3.read(
            method,
            extraData: Data(),
            transactionOptions: options)!
        let result = try tx.call()
        
        print("Got response for \(method)")
        if let success = result["_success"] as? Bool, !success {
            return ([Proposal](), InnerError.unsuccessfullСontractRead(description: "\(result)"))
        } else {
            let addresses = result["0"] as! [EthereumAddress]
            let proposals = result["1"] as! [[AnyObject]]
            let res = try parseProposals(addresses: addresses, proposals: proposals)
            print("\(method)\n\(res)")
            return (res, nil)
        }
    }
    
    private func parseProposals(addresses: [EthereumAddress], proposals: [[AnyObject]]) throws -> [Proposal] {
        var res: [Proposal] = []
        for (i, elem) in proposals.enumerated() {
            if elem.count < 8 {
                throw InnerError.structParseError(description: "Error proposal parse: \(elem)")
            }
            guard let metaUrl = elem[0] as? String,
                  let condData = elem[1] as? String,
                  let divorceTimeout = elem[2] as? BigUInt,
                  let timestamp = elem[3] as? BigUInt,
                  let authorAccepted = elem[4] as? Int,
                  let receiverAccepted = elem[5] as? Int,
                  let tokenId = elem[6] as? BigUInt,
                  let prevBlockNumber = elem[7] as? BigUInt else {
                      throw InnerError.structParseError(description: "Error proposal parse: \(elem)")
            }
            let proposal = Proposal(
                address: addresses[i].address,
                metaUrl: metaUrl,
                condData: condData,
                divorceTimeout: divorceTimeout,
                timestamp: timestamp,
                authorAccepted: authorAccepted == 1,
                receiverAccepted: receiverAccepted == 1,
                tokenId: tokenId,
                prevBlockNumber: prevBlockNumber
            )
            res.append(proposal)
        }
        return res
    }
    
    func getCurrentMarriage(address: String, onResult: @escaping (Marriage, Error?) -> ()) {
        if let walletAddress = EthereumAddress(address) {
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                do {
                    var options = TransactionOptions.defaultOptions
                    options.from = walletAddress
                    options.gasPrice = .automatic
                    options.gasLimit = .automatic
                    let tx = weddingContractWeb3.read(
                        "getCurrentMarriage",
                        extraData: Data(),
                        transactionOptions: options)!
                    let result = try tx.call()
                    
                    print("Got current marriage response:\n\(result)")
                    if let success = result["_success"] as? Bool, !success {
                        DispatchQueue.main.async {
                            onResult(Marriage(), InnerError.unsuccessfullСontractRead(description: "\(result)"))
                        }
                    } else {
                        let marriage = result["0"] as! [AnyObject]
                        print("marriage count: \(marriage.count)")
                        let res = try parseMarriage(marriage: marriage)
                        DispatchQueue.main.async {
                            onResult(res, nil)
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        onResult(Marriage(), error)
                    }
                }
            }
        } else {
            onResult(Marriage(), InnerError.invalidAddress(address: address))
        }
    }
    
    private func parseMarriage(marriage: [AnyObject]) throws -> Marriage {
        if marriage.count < 10 {
            throw InnerError.structParseError(description: "Error marriage parse: \(marriage)")
        }
        let divorceState = try parseDivorceState(marriage[2])
        guard let authorAddress = marriage[0] as? EthereumAddress,
              let receiverAddress = marriage[1] as? EthereumAddress,
              let divorceRequestTimestamp = marriage[3] as? BigUInt,
              let divorceTimeout = marriage[4] as? BigUInt,
              let timestamp = marriage[5] as? BigUInt,
              let metaUrl = marriage[6] as? String,
              let conditions = marriage[7] as? String,
              let tokenId = marriage[8] as? BigUInt,
              let prevBlockNumber = marriage[9] as? BigUInt else {
                  throw InnerError.structParseError(description: "Error marriage parse: \(marriage)")
        }
        if authorAddress.address == zeroAddress {
            return Marriage()
        }
        return Marriage(
            authorAddress: authorAddress.address,
            receiverAddress: receiverAddress.address,
            divorceState: divorceState,
            divorceRequestTimestamp: divorceRequestTimestamp,
            divorceTimeout: divorceTimeout,
            timestamp: timestamp,
            metaUrl: metaUrl,
            conditions: conditions,
            tokenId: tokenId,
            prevBlockNumber: prevBlockNumber)
    }
    
    private func parseDivorceState(_ state: AnyObject) throws -> DivorceState {
        guard let state = state as? BigUInt else {
            throw InnerError.structParseError(description: "Error marriage divorce state parse: \(state)")
        }
        switch state { //TODO: use enum method
        case 0:
            return .notRequested
        case 1:
            return .requestedByAuthor
        case 2:
            return .requestedByReceiver
        default:
            throw InnerError.structParseError(description: "Error marriage divorce state parse, unknown state: \(state)")
        }
    }
    
    func proposeData(to: String, metaUrl: String, condData: String) -> String? {
        let address = EthereumAddress(to)!
        return encodeFunctionData(method: "propose",
                                  parameters: [address as AnyObject,
                                               metaUrl as AnyObject,
                                               condData as AnyObject])?.toHexString(withPrefix: true)
    }
    
    func updatePropositionData(to: String, metaUrl: String, condData: String) -> String? {
        let address = EthereumAddress(to)!
        return encodeFunctionData(method: "updateProposition",
                                  parameters: [address as AnyObject,
                                               metaUrl as AnyObject,
                                               condData as AnyObject])?.toHexString(withPrefix: true)
    }
    
    func acceptPropositionData(to: String, metaUrl: String, condData: String) -> String? {
        let address = EthereumAddress(to)!
        let metaUrlHash = Tools.sha256(data: metaUrl.data(using: .utf8)!)
        let condDataHash = Tools.sha256(data: condData.data(using: .utf8)!)
        return encodeFunctionData(method: "acceptProposition",
                                  parameters: [address as AnyObject,
                                               metaUrlHash as AnyObject,
                                               condDataHash as AnyObject])?.toHexString(withPrefix: true)
    }
    
    func requestDivorceData() -> String? {
        return encodeFunctionData(method: "requestDivorce")?.toHexString(withPrefix: true)
    }
    
    func confirmDivorceData() -> String? {
        return encodeFunctionData(method: "confirmDivorce")?.toHexString(withPrefix: true)
    }
    
    private func encodeFunctionData(method: String, parameters: [AnyObject] = [AnyObject]()) -> Data? {
        let foundMethod = weddingContract.methods.filter { (key, value) -> Bool in
            return key == method
        }
        guard foundMethod.count == 1 else { return nil }
        let abiMethod = foundMethod[method]
        return abiMethod?.encodeParameters(parameters)
    }
    
    func proposeAgent(to: String, metaUrl: String, condData: String, onResult: @escaping (Error?) -> ()) {
        let address = EthereumAddress(to)!
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            callMethodByAgent(contract: weddingContractAgent,
                              method: "propose",
                              params: [address as AnyObject,
                                       metaUrl as AnyObject,
                                       condData as AnyObject],
                              onResult: onResult)
        }
    }
    
    func updatePropositionAgent(to: String, metaUrl: String, condData: String, onResult: @escaping (Error?) -> ()) {
        let address = EthereumAddress(to)!
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            callMethodByAgent(contract: weddingContractAgent,
                              method: "updateProposition",
                              params: [address as AnyObject,
                                       metaUrl as AnyObject,
                                       condData as AnyObject],
                              onResult: onResult)
        }
    }
    
    func acceptPropositionAgent(to: String, metaUrl: String, condData: String, onResult: @escaping (Error?) -> ()) {
        let address = EthereumAddress(to)!
        let metaUrlHash = Tools.sha256(data: metaUrl.data(using: .utf8)!)
        let condDataHash = Tools.sha256(data: condData.data(using: .utf8)!)
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            callMethodByAgent(contract: weddingContractAgent,
                              method: "acceptProposition",
                              params: [address as AnyObject,
                                       metaUrlHash as AnyObject,
                                       condDataHash as AnyObject],
                              onResult: onResult)
        }
    }
    
    func requestDivorceAgent(onResult: @escaping (Error?) -> ()) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            callMethodByAgent(contract: weddingContractAgent,
                              method: "requestDivorce",
                              params: [],
                              onResult: onResult)
        }
    }
    
    func confirmDivorceAgent(onResult: @escaping (Error?) -> ()) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            callMethodByAgent(contract: weddingContractAgent,
                              method: "confirmDivorce",
                              params: [],
                              onResult: onResult)
        }
    }
    
    private func callMethodByAgent(contract: web3.web3contract, method: String, params: [AnyObject], onResult: @escaping (Error?) -> ()) {
        do {
            let agentAccount = EthereumAddress(Config.agentAddress)!
            var options = TransactionOptions.defaultOptions
            options.value = Web3.Utils.parseToBigUInt("0.0", units: .eth)
            options.from = agentAccount
            options.gasPrice = .automatic
            options.gasLimit = .automatic
            print("calling method by agent: \(method)")
            let tx = contract.write(
                method,
                parameters: params,
                extraData: Data(),
                transactionOptions: options)!
            let res = try tx.send()
            DispatchQueue.main.async {
                print(res)
                onResult(nil)
            }
        } catch {
            DispatchQueue.main.async {
                onResult(error)
            }
        }
    }
}
