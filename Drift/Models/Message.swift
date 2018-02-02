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
    var attachmentIds: [Int] = []
    var attachments: [Attachment] = []
    var contentType = ContentType.Chat.rawValue
    var createdAt = Date()
    var authorId: Int!
    var authorType: AuthorType!
    var type: Type!
    var context: Context?
    
    var conversationId: Int!
    var requestId: Double = 0
    var sendStatus: SendStatus = SendStatus.Sent
    var formattedBody: NSMutableAttributedString?
    var viewerRecipientStatus: RecipientStatus?
    
    var preMessages: [PreMessage] = []

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
        
        body = TextHelper.cleanString(body: body ?? "")
        
        
        attachmentIds           <- map["attachments"]
        contentType             <- map["contentType"]
        createdAt               <- (map["createdAt"], DriftDateTransformer())
        authorId                <- map["authorId"]
        authorType              <- map["authorType"]
        type                    <- map["type"]
        conversationId          <- map["conversationId"]
        viewerRecipientStatus  <- map["viewerRecipientStatus"]
        preMessages             <- map["attributes.preMessages"]

        do {
            let htmlStringData = (body ?? "").data(using: String.Encoding.utf8)!
            let attributedHTMLString = try NSMutableAttributedString(data: htmlStringData, options: [NSAttributedString.DocumentReadingOptionKey.documentType : NSAttributedString.DocumentType.html, NSAttributedString.DocumentReadingOptionKey.characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)

            if let font = UIFont(name: "AvenirNext-Regular", size: 16){
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.paragraphSpacing = 0.0
                attributedHTMLString.addAttributes([NSAttributedStringKey.font: font, NSAttributedStringKey.paragraphStyle: paragraphStyle], range: NSRange(location: 0, length: attributedHTMLString.length))
                formattedBody = attributedHTMLString
            }
        }catch{
            //Unable to format HTML body, in this scenario the raw html will be shown in the message cell
        }
    }

    open func toMessageJSON() -> [String: Any]{
        
        var json:[String : Any] = [
            "body": body ?? "",
            "contentType": contentType,
            "type": type.rawValue,
            "attachments": attachmentIds
        ]
        
        if let context = context {
            json["context"] = context.toJSON()
        }
        
        return json
    }
}

extension Array where Iterator.Element == Message
{
    
    mutating func sortMessagesForConversation() -> Array {
        
        for message in self {
            if !message.preMessages.isEmpty {
                self.append(contentsOf: getMessagesFromPreMessages(message: message, preMessages: message.preMessages))
            }
        }
        
        sorted(by: { $0.createdAt.compare($1.createdAt as Date) == .orderedDescending})
        
        return self
    }
    
    private func getMessagesFromPreMessages(message: Message, preMessages: [PreMessage]) -> [Message] {
        
        let date = message.createdAt
        var output: [Message] = []
        for (index, preMessage) in preMessages.enumerated() {
            let fakeMessage = Message()
            
            fakeMessage.createdAt = date.addingTimeInterval(TimeInterval(-(index + 1)))
            fakeMessage.conversationId = message.conversationId
            fakeMessage.body = TextHelper.cleanString(body: preMessage.messageBody)
//            fakeMessage.saveFormattedString()
            
            fakeMessage.uuid = UUID().uuidString
            
            fakeMessage.sendStatus = .Sent
            fakeMessage.contentType = ContentType.Chat.rawValue
            fakeMessage.authorType = AuthorType.User
            
            if let sender = preMessage.user {
                fakeMessage.authorId = sender.userId
                output.append(fakeMessage)
            }
        }
        
        return output
    }
    
}


func ==(lhs: Message, rhs: Message) -> Bool {
    return lhs.uuid == rhs.uuid
}

