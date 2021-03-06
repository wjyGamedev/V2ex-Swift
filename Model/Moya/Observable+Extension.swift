//
//  Observable+Extension.swift
//  V2ex-Swift
//
//  Created by huangfeng on 2018/6/11.
//  Copyright © 2018 Fin. All rights reserved.
//

import UIKit
import RxSwift
import ObjectMapper
import SwiftyJSON
import Moya
import Ji

public enum ApiError : Swift.Error {
    case Error(info: String)
    case AccountBanned(info: String)
    case LoginPermissionRequired(info: String)
}

extension Swift.Error {
    func rawString() -> String {
        guard let err = self as? ApiError else {
            return self.localizedDescription
        }
        switch err {
        case let .Error(info):
            return info
        case let .AccountBanned(info):
            return info
        case let .LoginPermissionRequired(info):
            return info
        }
    }
}

extension Observable where Element: Moya.Response {
    /// 过滤 HTTP 错误，例如超时，请求失败等
    func filterHttpError() -> Observable<Element> {
        return filter{ response in
            if (200...209) ~= response.statusCode {
                return true
            }
            print("网络错误")
            throw ApiError.Error(info: "网络错误")
        }
    }

//MARK: - JSON解析相关
    
    /// 过滤逻辑错误，例如协议里返回 错误CODE
    func filterResponseError() -> Observable<JSON> {
        return filterHttpError().map({ (response) -> JSON in
            
            let json = JSON(data: response.data)
            var code = 200
            var msg = ""
            if let codeStr = json["code"].rawString(), let c = Int(codeStr)  {
                code = c
            }
            if json["msg"].exists() {
                msg = json["msg"].rawString()!
            }
            else if json["message"].exists() {
                msg = json["message"].rawString()!
            }
            else if json["info"].exists() {
                msg = json["info"].rawString()!
            }
            else if json["description"].exists() {
                msg = json["description"].rawString()!
            }
            if (code == 200 || code == 99999 || code == 80001 || code == 1){
                return json
            }
            
            switch code {
            default: throw ApiError.Error(info: msg)
            }
        })
    }
    
    /// 将Response 转换成 JSON Model
    ///
    /// - Parameters:
    ///   - typeName: 要转换的Model Class
    ///   - dataPath: 从哪个节点开始转换，例如 ["data","links"]
    func mapResponseToObj<T: Mappable>(_ typeName: T.Type , dataPath:[String] = [] ) -> Observable<T> {
        return filterResponseError().map{ json in
            var rootJson  = json
            if dataPath.count > 0{
                rootJson = rootJson[dataPath]
            }
            if let model: T = self.resultFromJSON(json: rootJson)  {
                return model
            }
            else{
                throw ApiError.Error(info: "json 转换失败")
            }
        }
    }
    
    /// 将Response 转换成 JSON Model Array
    func mapResponseToObjArray<T: Mappable>(_ type: T.Type, dataPath:[String] = [] ) -> Observable<[T]> {
        return filterResponseError().map{ json in
            var rootJson = json;
            if dataPath.count > 0{
                rootJson = rootJson[dataPath]
            }
            var result = [T]()
            guard let jsonArray = rootJson.array else{
                return result
            }
            
            for json in  jsonArray{
                if let jsonModel: T = self.resultFromJSON(json: json) {
                    result.append(jsonModel)
                }
                else{
                    throw ApiError.Error(info: "json 转换失败")
                }
            }
            
            return result
        }
    }
    
    private func resultFromJSON<T: Mappable>(jsonString:String) -> T? {
        return T(JSONString: jsonString)
    }
    private func resultFromJSON<T: Mappable>(json:JSON) -> T? {
        if let str = json.rawString(){
            return resultFromJSON(jsonString: str)
        }
        return nil
    }
    
//MARK: - Ji 解析相关
    
    /// 过滤业务逻辑错误
    func filterJiResponseError() -> Observable<Ji> {
        return filterHttpError().map({ (response) -> Ji in
            if response.response?.url?.path == "/signin" && response.request?.url?.path != "/signin" {
                throw ApiError.LoginPermissionRequired(info: "查看的内容需要登录!")
            }
            
            if let jiHtml = Ji(htmlData: response.data) {
                return jiHtml
            }
            else {
                throw ApiError.Error(info: "Failed to serialize response.")
            }
        })
    }
    
    
    /// 将Response 转成成 Ji Model Array
    func mapResponseToJiArray<T: HtmlModelArrayProtocol>(_ type: T.Type) -> Observable<[T]> {
        return filterJiResponseError().map{ ji in
            return type.createModelArray(ji: ji)
        }
    }
    
    /// 将Response 转成成 Ji Model
    func mapResponseToJiModel<T: HtmlModelProtocol>(_ type: T.Type) -> Observable<T> {
        return filterJiResponseError().map{ ji in
            return type.createModel(ji: ji)
        }
    }
}

