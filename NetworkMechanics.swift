//
//  network.swift
//  StatMe
//
//  Created by David Schmotz on 08.03.18.
//  Copyright © 2018 DavidSchmotz. All rights reserved.
//

import Foundation
import SystemConfiguration

class NetworkMechanics {
    
    var ipv4 = String()
    var ipv6 = String()
    var port4 = Int()
    var port6 = Int()
    var endTag = String()
    
    init(ipv4: String?, ipv6: String?, port4: Int?, port6: Int?, endTag: String?) {
        self.ipv4 = ipv4 ?? "127.0.0.1"
        self.ipv6 = ipv6 ?? "::1"
        self.port4 = port4 ?? 5050
        self.port6 = port6 ?? 5051
        self.endTag = endTag ?? "end"
    }
    
    func sendAndReceive(requestMessage: String, answer: UnsafeMutablePointer<String>) {
        let socket = determineSocket()
        
        //  Define Streams
        var inputStream :InputStream?
        var outputStream :OutputStream?
        Stream.getStreamsToHost(withName: socket.ipAddress, port: socket.port, inputStream: &inputStream, outputStream: &outputStream)
        if inputStream != nil && outputStream != nil {
            answer.pointee = "Konnte den Server nicht erreichen"
        }
        //  Open Streams after making sure they are created accordingly
        inputStream!.open()
        outputStream!.open()
        DispatchQueue.global(qos: .background).async {
            while true {
                //print(inputStream!.hasBytesAvailable)
            }
        }
        
        send(message: requestMessage, to: &outputStream)
        answer.pointee = readAll(from: &inputStream)
        outputStream!.close()
    }
    
    func send(message: String, to: AutoreleasingUnsafeMutablePointer<OutputStream?>!) {
        //  Create Buffer of the message
        var buffer :[UInt8] = Array(message.utf8)
        //  Send message
        to.pointee!.write(&buffer, maxLength: buffer.count)
    }
    
    func readAll(from: AutoreleasingUnsafeMutablePointer<InputStream?>!) -> String {
        let bufferSize = 2048
        var fullMessage = NSString()
        var byteCount = 0
        while true {
            print("still listening")
            var buffer = Array<UInt8>(repeating: 0, count: bufferSize)
            let bytesRead = from.pointee!.read(&buffer, maxLength: bufferSize)
            byteCount += bytesRead
            let output = NSString(bytes: &buffer, length: bufferSize, encoding: String.Encoding.utf8.rawValue)
            fullMessage = NSString(format: "%@%@", fullMessage, output!)
            if (output?.contains(self.endTag))! {
                print("breaking")
                break
            }
        }
        print(from.pointee!.hasBytesAvailable)
        from.pointee!.close()
        if byteCount >= 0 {
            var resultingMessage = String(fullMessage)
            return resultingMessage.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        } else {
            // Handle error
            return "Could not read any bytes"
        }
    }
    
    func serialiseString(message: String, seperator: String, headerLength: Int, numberOfParameters: Int) -> [[String]] {
        let valid = checkParametersForValidity(message: message, seperator: seperator, headerLength: headerLength, numberOfParameters: numberOfParameters)
        if !valid {
            return [["Fehler"]]
        }
        var result = [[String]]()
        
        var explodedMessage = message.components(separatedBy: seperator)
        explodedMessage.removeSubrange(ClosedRange(uncheckedBounds: (lower: 0, upper: headerLength)))
        let header = Array(explodedMessage[0...headerLength])
        
        //  Add an Array for each expected parameter
        //  Up until this point the array has to have only one element and that is the header
        for i in 0..<numberOfParameters {
            result.append([String]())
        }
        
        // Serialization Process
        for iterationIndex in stride(from: 0, to: explodedMessage.count-1, by: numberOfParameters) {
            for localIndex in 0...numberOfParameters {
                let combinedIndex = iterationIndex + localIndex
                result[localIndex].append(explodedMessage[combinedIndex])
            }
        }
        
        result.insert(header, at: 0)
        return result
    }
    
    func checkParametersForValidity(message: String, seperator: String, headerLength: Int, numberOfParameters: Int) -> Bool {
        let explodedMessage = message.components(separatedBy: seperator)
        let lengthWithoutHeader = explodedMessage.count - headerLength
        let remainder = lengthWithoutHeader % numberOfParameters
        return remainder == 0
    }
    
    func determineSocket() -> Socket {
        var socket = Socket()
        
        if checkNetworkForIP() {
            socket = Socket(
                ipV6 : true,
                ipAddress : self.ipv6,
                port: self.port4
            )
        } else {
            socket = Socket(
                ipV6 : false,
                ipAddress : self.ipv4,
                port: self.port4
            )
        }
        
        return socket
    }
    
    
    func checkNetworkForIP() -> Bool {
        print("checkNetworkForIP is called")
        
        var address : String?
        var boolval = Bool()
        
        if isConnectedToNetwork() {
            boolval = false
        } else {
            // Get list of all interfaces on the local machine:
            var ifaddr : UnsafeMutablePointer<ifaddrs>? = nil
            if getifaddrs(&ifaddr) == 0 {
                // For each interface ...
                var ptr = ifaddr
                while ptr != nil {
                    defer { ptr = ptr?.pointee.ifa_next }
                    let interface = ptr?.pointee
                    // Check for IPv4 or IPv6 interface:
                    let addrFamily = interface?.ifa_addr.pointee.sa_family
                    if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                        // Check interface name:
                        if let name = String(validatingUTF8: (interface?.ifa_name)!), name == "en0" {
                            // Convert interface address to a human readable string:
                            var addr = interface?.ifa_addr.pointee
                            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                            getnameinfo(&addr!, socklen_t((interface?.ifa_addr.pointee.sa_len)!),
                                        &hostname, socklen_t(hostname.count),
                                        nil, socklen_t(0), NI_NUMERICHOST)
                            address = String(cString: hostname)
                        }
                    }
                }
                
                freeifaddrs(ifaddr)
            }
            
            if address!.components(separatedBy: ":").count > 1 {
                print(address!.components(separatedBy: ":").count)
                boolval = true
            } else if address!.components(separatedBy: ".").count > 1 {
                print(address!.components(separatedBy: ".").count)
                boolval = false
            }
        }
        
        return boolval
    }
    
    
    
    func isConnectedToNetwork() -> Bool {
        print("isConnectedToNetwork is called")
        
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout.size(ofValue: zeroAddress))
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        guard let defaultRouteReachability = withUnsafePointer(to: &zeroAddress, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {zeroSockAddress in
                SCNetworkReachabilityCreateWithAddress(nil, zeroSockAddress)
            }
        }) else {
            return false
        }
        
        var flags : SCNetworkReachabilityFlags = []
        if !SCNetworkReachabilityGetFlags(defaultRouteReachability, &flags) {
            return false
        }
        
        let isReachable = flags.contains(.reachable)
        let needsConnection = flags.contains(.connectionRequired)
        let cellular = flags.contains(.isWWAN)
        
        return (cellular)
    }
}
