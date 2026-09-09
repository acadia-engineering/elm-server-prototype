module Resolver exposing
  ( Resolver
  , succeed
  , fail
  , andThen
  , with
  --
  , query
  , post
  , http
  --
  , run
  )


import Bytes exposing (Bytes)
import Bytes.Decode as D
import Bytes.Encode as E
import Json.Decode as JD
import Json.Encode as JE
import Http
import Task exposing (Task)

import Acadia.Transaction exposing (Transaction(..))



-- RESOLVER


type Resolver a =
  Resolver (Task () a)


succeed : a -> Resolver a
succeed a =
  Resolver <| Task.succeed a


fail : Resolver a
fail =
  Resolver <| Task.fail ()


andThen : (a -> Resolver b) -> Resolver a -> Resolver b
andThen cont (Resolver task) =
  Resolver <| Task.andThen (\a -> unwrap (cont a)) task


with : Resolver a -> (a -> Resolver b) -> Resolver b
with (Resolver task) cont =
  Resolver <| Task.andThen (\a -> unwrap (cont a)) task


unwrap : Resolver a -> Task () a
unwrap (Resolver task) =
  task


run : (Maybe a -> msg) -> Resolver a -> Cmd msg
run toMsg (Resolver task) =
  Task.attempt (toMsg << Result.toMaybe) task



-- DATABASE QUERIES


query : Transaction a -> Resolver (Maybe a)
query (Transaction encoder decoder) =
  Resolver <| toMaybe <|
    Http.task
      { method = "POST"
      , headers = []
      , url = "http://localhost:9000/_endpoints"
      , body = Http.bytesBody "application/octet-stream" (E.encode encoder)
      , resolver = Http.bytesResolver (decodeBytes decoder)
      , timeout = Just 60000
      }


decodeBytes : D.Decoder a -> (Http.Response Bytes -> Result () a)
decodeBytes decoder =
 \response ->
    case response of
      Http.BadUrl_ _       -> Err ()
      Http.Timeout_        -> Err ()
      Http.NetworkError_   -> Err ()
      Http.BadStatus_  _ _ -> Err ()
      Http.GoodStatus_ _ b ->
        case D.decode decoder b of
          Just a  -> Ok a
          Nothing -> Err ()



-- POST


post :
  { url : String
  , body : Http.Body
  , decoder : JD.Decoder a
  }
  -> Resolver (Maybe a)
post {url,body,decoder} =
  http
    { method = "POST"
    , headers = []
    , url = url
    , body = body
    , resolver = Http.stringResolver (decodeJson decoder)
    , timeout = Just 60000
    }


decodeJson : JD.Decoder a -> (Http.Response String -> Result () a)
decodeJson decoder =
 \response ->
    case response of
      Http.BadUrl_ _       -> Err ()
      Http.Timeout_        -> Err ()
      Http.NetworkError_   -> Err ()
      Http.BadStatus_  _ _ -> Err ()
      Http.GoodStatus_ _ b ->
        case JD.decodeString decoder b of
          Ok  a -> Ok a
          Err _ -> Err ()



-- HTTP


http :
  { method : String
  , headers : List Http.Header
  , url : String
  , body : Http.Body
  , resolver : Http.Resolver () a
  , timeout : Maybe Float
  }
  -> Resolver (Maybe a)
http details =
  Resolver <| toMaybe <| Http.task details



-- TASK HELPERS


toMaybe : Task x a -> Task y (Maybe a)
toMaybe task =
  Task.map Just task
    |> Task.onError (\_ -> Task.succeed Nothing)
