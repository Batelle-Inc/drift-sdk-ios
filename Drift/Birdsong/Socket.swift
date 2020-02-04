//
//  Socket.swift
//  Pods
//
//  Created by Simon Manning on 23/06/2016.
//
//

import Foundation
import Starscream

final class Socket {
    // MARK: - Convenience aliases
    typealias Payload = [String: Any]
    
    // MARK: - Properties
    
    fileprivate var socket: WebSocket
    var enableLogging = true
    
    var onConnect: (() -> ())?
    var onDisconnect: ((Error?) -> ())?
    
    fileprivate(set) var channels: [String: Channel] = [:]
    
    fileprivate static let HeartbeatInterval = Int64(30 * NSEC_PER_SEC)
    fileprivate static let HeartbeatPrefix = "hb-"
    fileprivate var heartbeatQueue: DispatchQueue
    
    fileprivate var awaitingResponses = [String: Push]()
    
    var isConnected: Bool {
        return socket.isConnected
    }
    
    // MARK: - Initialisation
    
    init(url: URL, params: [String: String]? = nil, callbackQueue: DispatchQueue) {
        heartbeatQueue = DispatchQueue(label: "com.drift.sdk.hbqueue", attributes: [])
        socket = WebSocket(url: buildURL(url, params: params))
        socket.delegate = self
        socket.callbackQueue = callbackQueue
    }
    
    // MARK: - Connection
    
    func connect() {
        if socket.isConnected {
            return
        }
        
        log("Connecting to: \(socket.currentURL)")
        socket.connect()
    }
    
    public func disconnect() {
        if !socket.isConnected {
            return
        }
        
        log("Disconnecting from: \(socket.currentURL)")
        socket.disconnect()
    }
    
    // MARK: - Channels
    
    func channel(_ topic: String, payload: Payload = [:]) -> Channel {
        let channel = Channel(socket: self, topic: topic, params: payload)
        channels[topic] = channel
        return channel
    }
    
    func remove(_ channel: Channel) {
        channel.leave()?.receive("ok") { [weak self] response in
            self?.channels.removeValue(forKey: channel.topic)
        }
    }
    
    // MARK: - Heartbeat
    
    func sendHeartbeat() {
        guard socket.isConnected else {
            return
        }
        
        let ref = Socket.HeartbeatPrefix + UUID().uuidString
        _ = send(Push(Event.Heartbeat, topic: "phoenix", payload: [:], ref: ref))
        queueHeartbeat()
    }
    
    func queueHeartbeat() {
        let time = DispatchTime.now() + Double(Socket.HeartbeatInterval) / Double(NSEC_PER_SEC)
        heartbeatQueue.asyncAfter(deadline: time) {
            self.sendHeartbeat()
        }
    }
    
    // MARK: - Sending data
    
    func send(_ event: String, topic: String, payload: Payload) -> Push {
        let push = Push(event, topic: topic, payload: payload)
        return send(push)
    }
    
    func send(_ message: Push) -> Push {
        if !socket.isConnected {
            message.handleNotConnected()
            return message
        }

        do {
            let data = try message.toJson()
            log("Sending: \(message.payload)")
            if let ref = message.ref {
                awaitingResponses[ref] = message
                socket.write(data: data, completion: nil)
            }
        } catch let error as NSError {
            log("Failed to send message: \(error)")
            message.handleParseError()
        }
        
        return message
    }
    
    // MARK: - Event constants
    
    struct Event {
        static let Heartbeat = "heartbeat"
        static let Join = "phx_join"
        static let Leave = "phx_leave"
        static let Reply = "phx_reply"
        static let Error = "phx_error"
        static let Close = "phx_close"
    }
}

extension Socket: WebSocketDelegate {

    // MARK: - WebSocketDelegate
    public func websocketDidConnect(socket: WebSocketClient) {
        log("Connected to: \(socket)")
        onConnect?()
        queueHeartbeat()
    }
    
    public func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        log("Disconnected from: \(socket)")
        onDisconnect?(error)
        
        // Reset state.
        awaitingResponses.removeAll()
        channels.removeAll()
    }
    
    public func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        
        if let data = text.data(using: String.Encoding.utf8),
            let response = Response(data: data) {
            defer {
                awaitingResponses.removeValue(forKey: response.ref)
            }
            
            log("Received message: \(response.payload)")
            
            if let push = awaitingResponses[response.ref] {
                push.handleResponse(response)
            }
            
            channels[response.topic]?.received(response)
        } else {
            fatalError("Couldn't parse response: \(text)")
        }
    }
    
    public func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        log("Received data: \(data)")
    }
}

// MARK: - Logging

extension Socket {
    fileprivate func log(_ message: String) {
        if enableLogging {
            print("[Birdsong]: \(message)")
        }
    }
}

// MARK: - Private URL helpers

private func buildURL(_ url: URL, params: [String: String]?) -> URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
        let params = params else {
            return url
    }
    
    var queryItems = [URLQueryItem]()
    params.forEach({
        queryItems.append(URLQueryItem(name: $0, value: $1))
    })
    
    components.queryItems = queryItems
    
    guard let url = components.url else { fatalError("Problem with the URL") }
    
    return url
}
