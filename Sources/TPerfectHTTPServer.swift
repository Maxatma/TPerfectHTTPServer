//
//  TPerfectHTTPServer.swift
//  TPerfectHTTPServer
//
//  Created by Christopher Simpson on 10/28/16.
//
//

import PerfectLib
import PerfectHTTP
import PerfectHTTPServer
import Thrift
import Foundation
import PerfectRequestLogger
import Dispatch

let pQueue = DispatchQueue(label: "THttpServer.process.q", qos: .userInitiated, attributes: .concurrent)


open class TPerfectHTTPServer<InProtocol: TProtocol, OutProtocol: TProtocol, Processor: TProcessor, Service> where Processor.Service == Service {

 private var server = HTTPServer()
 var serviceHandler: Service

 public init(address: String? = nil,
             path: String? = nil,
             port: Int,
             service: Service,
             inProtocol: InProtocol.Type,
             outProtocol: OutProtocol.Type?=nil,
             processor: Processor.Type) throws {

   // set service handler
   self.serviceHandler = service

   if let address = address {
     server.serverAddress = address
   }
   server.serverPort = UInt16(port)

   var routes = Routes()
   var uri = "/"
   if let path = path {
     uri += path
   }
   routes.add(method: .post, uri: uri) { request, response in
     pQueue.async {
       response.setHeader(.contentType, value: "application/x-thrift")

       let itrans = TMemoryBufferTransport()
       if let bytes = request.postBodyBytes {
         let data = Data(bytes: bytes)
         itrans.reset(readBuffer: data)
       }

       let otrans = TMemoryBufferTransport(flushHandler: { trans, buff in
         let array = buff.withUnsafeBytes {
           Array<UInt8>(UnsafeBufferPointer(start: $0, count: buff.count))
         }
         response.status = .ok
         response.setBody(bytes: array)
         response.completed()
       })

       let inproto = InProtocol(on: itrans)
       let outproto = OutProtocol(on: otrans)

       do {
         let proc = Processor(service: self.serviceHandler)
         try proc.process(on: inproto, outProtocol: outproto)
         try otrans.flush()
       } catch {
         response.status = .badRequest
         response.completed()
       }
     }
   }
   server.addRoutes(routes)
   // Instantiate a logger
   let myLogger = RequestLogger()
  
   // Add the filters
   // Request filter at high priority to be executed first
   server.setRequestFilters([(myLogger, .high)])
   // Response filter at low priority to be executed last
   server.setResponseFilters([(myLogger, .low)])
 }

 public func serve() throws {
   try server.start()
 }
}
