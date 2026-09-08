port module Server exposing
  ( Server
  , serve
  --
  , Request
  , Body
  --
  , Response
  , empty
  , string
  , File
  , file
  , proxy
  --
  , Header
  , header
  )


import Dict exposing (Dict)
import Json.Decode as D
import Json.Encode as E

import Resolver exposing (Resolver)



-- SERVER


type alias Server =
  Program () Model Msg


type alias Model = ()


type Msg
  = Accepted Handle Request
  | Rejected Handle
  | Resolved Handle (Maybe Response)


serve : (Request -> Resolver Response) -> Program () Model Msg
serve toResolver =
  Platform.worker
    { init = \() -> ((), Cmd.none)
    , update = \msg () ->
        case msg of
          Accepted handle req ->
            ((), Resolver.run (Resolved handle) (toResolver req))

          Rejected handle ->
            ((), respond handle (empty 400 []))

          Resolved handle result ->
            case result of
              Just r  -> ((), respond handle  r         )
              Nothing -> ((), respond handle (empty 500 []))
    , subscriptions = \() -> accept
    }



-- REQUESTS


type alias Request =
  { method : String
  , url : String
  , headers : Dict String String
  , body : Maybe Body
  }


type alias Body =
  { tipe : String
  , content : String
  }


dRequest : D.Decoder Request
dRequest =
  D.map4 Request
    (D.field "method" D.string)
    (D.field "url" D.string)
    (D.field "headers" (D.dict D.string))
    (D.maybe dBody)


dBody : D.Decoder Body
dBody =
  D.map2 Body
    (D.field "headers" (D.field "content-type" D.string))
    (D.field "__elm_body" (D.map String.concat (D.list D.string)))



-- RESPONSES


type Response =
  Response E.Value


empty : Int -> List Header -> Response
empty code headers =
  Response <| E.object <|
    [ ("tag", E.string "empty")
    , ("code", E.int code)
    , ("headers", eHeaders headers)
    ]


string : Int -> List Header -> String -> String -> Response
string code headers tipe body =
  Response <| E.object <|
    [ ("tag", E.string "string")
    , ("code", E.int code)
    , ("headers", eHeaders headers)
    , ("tipe", E.string tipe)
    , ("body", E.string body)
    ]


type alias File =
  { tipe : String
  , path : String
  }


file : Int -> List Header -> File -> Response
file code headers {tipe,path} =
  Response <| E.object <|
    [ ("tag", E.string "file")
    , ("code", E.int code)
    , ("headers", eHeaders headers)
    , ("tipe", E.string tipe)
    , ("path", E.string path)
    ]


proxy : String -> Int -> Response
proxy hostname port_ =
  Response <| E.object <|
    [ ("tag", E.string "proxy")
    , ("hostname", E.string hostname)
    , ("port", E.int port_)
    ]



-- HEADERS


type Header = Header String String


header : String -> String -> Header
header =
  Header


eHeaders : List Header -> E.Value
eHeaders headers =
  E.object <| List.map (\(Header k v) -> (k, E.string v)) headers



-- NODEJS REQUEST PORT
--
-- The request/response pair serves as a "handle" to identify each
-- connection. The handle is sent out with the response where nodejs
-- finishes sending a response.


type Handle =
  Handle Handle_


type alias Handle_ =
  { req : E.Value
  , res : E.Value
  }


port requests : (Handle_ -> msg) -> Sub msg


accept :  Sub Msg
accept =
  requests <| \handle ->
    case D.decodeValue dRequest handle.req of
      Ok req -> Accepted (Handle handle) req
      Err _  -> Rejected (Handle handle)



-- NODEJS RESPONSE PORT
--
-- Send out the request/response pair, along with some JSON describing
-- the desired response.


type alias ResponseData =
  { req : E.Value
  , res : E.Value
  , content : E.Value
  }


port responses : ResponseData -> Cmd msg


respond : Handle -> Response -> Cmd msg
respond (Handle handle) (Response content) =
  responses { req = handle.req, res = handle.res, content = content }

