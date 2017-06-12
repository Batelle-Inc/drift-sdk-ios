//
//  Message.swift
//  Drift
//
//  Created by Brian McDonald on 25/07/2016.
//  Copyright © 2016 Drift. All rights reserved.
//


import ObjectMapper

enum ContentType: String{
    case Chat = "CHAT"
    case NPS = "NPS_QUESTION"
    case Annoucement = "ANNOUNCEMENT"
}

enum Type: String{
    case Chat = "CHAT"
}

enum AuthorType: String{
    case User = "USER"
    case EndUser = "END_USER"
}

enum SendStatus: String{
    case Sent = "SENT"
    case Pending = "PENDING"
    case Failed = "FAILED"
}

enum RecipientStatus: String {
    case Sent = "Sent"
    case Delivered = "Delivered"
    case Read = "Read"
}

class Message: Mappable, Equatable, Hashable{
    var id: Int!
    var uuid: String?
    var inboxId: Int!
    var body: String?
    var attachments: [Int] = []
    var contentType = ContentType.Chat.rawValue
    var createdAt = Date()
    var authorId: Int!
    var authorType: AuthorType!
    var type: Type!
    var context: Context?
    
    var conversationId: Int!
    var requestId: Double = 0
    var sendStatus: SendStatus = SendStatus.Sent
    var formattedBody: NSAttributedString?
    var viewerReceipientStatus: RecipientStatus?
    
    var hashValue: Int {
        return id
    }
    
    required convenience init?(map: Map) {
        if map.JSON["contentType"] as? String == nil || ContentType(rawValue: map.JSON["contentType"] as! String) == nil{
            return nil
        }
        
        if let body = map.JSON["body"] as? String, let attachments = map.JSON["attachments"] as? [Int]{
            if body == "" && attachments.count == 0{
                return nil
            }
        }
        self.init()
    }
    
    func mapping(map: Map) {
        id                      <- map["id"]
        uuid                    <- map["uuid"]
        inboxId                 <- map["inboxId"]
        body                    <- map["body"]
        
        if body != nil {
            if let range = body!.range(of: "<p>", options: .caseInsensitive) {
                body!.replaceSubrange(range, with: "")
            }
            
            if let range = body!.range(of: "</p>", options: .backwards) {
                body!.replaceSubrange(range, with: "")
            }
            
            if let _ = body!.range(of: "<hr", options: .caseInsensitive) {
                body = body!.replacingOccurrences(of: "<hr [^>]+>", with: "", options: String.CompareOptions.regularExpression, range: nil)
            }
            
        }
        
        attachments             <- map["attachments"]
        contentType             <- map["contentType"]
        createdAt               <- (map["createdAt"], DriftDateTransformer())
        authorId                <- map["authorId"]
        authorType              <- map["authorType"]
        type                    <- map["type"]
        conversationId          <- map["conversationId"]
        context                 <- map["context"]
        viewerReceipientStatus  <- map["viewerReceipientStatus"]

        do {
            let htmlStringData = (body ?? "").data(using: String.Encoding.utf8)!
            let attributedHTMLString = try NSMutableAttributedString(data: htmlStringData, options: [NSDocumentTypeDocumentAttribute : NSHTMLTextDocumentType, NSCharacterEncodingDocumentAttribute: String.Encoding.utf8.rawValue, ], documentAttributes: nil)
            
            if let font = UIFont(name: "AvenirNext-Regular", size: 16){
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.paragraphSpacing = 0.0
                attributedHTMLString.addAttributes([NSFontAttributeName: font, NSParagraphStyleAttributeName: paragraphStyle], range: NSRange(location: 0, length: attributedHTMLString.length))
                formattedBody = attributedHTMLString
            }
        }catch{
            //Unable to format HTML body, in this scenario the raw html will be shown in the message cell
        }
    }

}

func ==(lhs: Message, rhs: Message) -> Bool {
    return lhs.uuid == rhs.uuid
}

