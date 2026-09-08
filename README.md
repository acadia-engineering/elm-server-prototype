# Experiment with Elm on the server

I want to write nice beautiful types in Elm and Acadia and use them everywhere! This little script runs an Elm program as a simple HTTP server.

```
┌──────┐      ┌──────┐      ┌────────┐
│client│ <──> │server│ <──> │database│
└──────┘      └──────┘      └────────┘
  Elm           Elm           Acadia
```

This prototype is mostly for demonstration purposes. I am having some fun and exploring some design ideas. Hopefully it gives you some idea where Acadia is heading!


## Setup

You will need [Elm](https://guide.elm-lang.org/install/elm.html), [Acadia](https://acadia.engineering/download), and [Node.js](https://nodejs.org/) installed for this.

```bash
# Download the Acadia examples, navigate to the 3rd example
git clone https://github.com/acadia-engineering/examples.git
cd examples
cd 03-users

# run the example
git clone https://github.com/acadia-engineering/elm-server-prototype.git
bash elm-server-prototype/serve.sh
```

You can explore this example in detail [here](https://github.com/acadia-engineering/examples/tree/main/03-users).

And check out the bash script for yourself! You can tweak it to your liking. The point of this prototype is that it is pretty easy to try things out. Everything is accomplished with features like [`Platform.worker`](https://package.elm-lang.org/packages/elm/core/latest/Platform#worker) that have been in Elm since 2016.


## API

The little bash script creates `Server` and `Resolver` modules that you can use from your server written in Elm. Again, check out [this example](https://github.com/acadia-engineering/examples/tree/main/03-users) to see these modules in action.

```elm
module Server exposing (..)

-- A server is just a function from requests to responses.

type Server

serve : (Request -> Resolver Response) -> Server

-- Requests are simple data structures.

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

-- Most responses take a HTTP status code (like 200 or 404),
-- a list of headers, and whatever data goes in the body.
-- The `proxy` response takes a hostname and port number.

type Response

empty  : Int -> List Header -> Response
string : Int -> List Header -> String -> String -> Response
file   : Int -> List Header -> File -> Response
proxy  : String -> Int -> Response

type alias File =
  { tipe : String
  , path : String
  }

-- Headers are just key value pairs. No escaping at the moment.

type Header

header : String -> String -> Header
```

A `Resolver` can run HTTP requests, so you can gather a little bit of data on the server. Typical uses would be talking to Acadia, sending emails, talking to stripe, etc.

```elm
module Resolver exposing (..)

-- Resolvers can be composed like Maybe, Result, Task, Transaction, etc.

type Resolver a

succeed : a -> Resolver a
fail : Resolver a

andThen : (a -> Resolver b) -> Resolver a -> Resolver b
with : Resolver a -> (a -> Resolver b) -> Resolver b

run : (Maybe a -> msg) -> Resolver a -> Cmd msg

-- Make some HTTP requests

query : Transaction a -> Resolver (Maybe a)

post :
  { url : String
  , body : Http.Body
  , decoder : D.Decoder a
  }
  -> Resolver (Maybe a)

http :
  { method : String
  , headers : List Http.Header
  , url : String
  , body : Http.Body
  , resolver : Http.Resolver () a
  , timeout : Maybe Float
  }
  -> Resolver (Maybe a)
```

The resolver type is very limited on purpose. I want to keep the set of possible effects basically aligned with Elm. I have no ambition to add file I/O primitives here. The goal is offer a “high-speed rail” network for your programs.


## High-Speed Rail and the Functional Fast Path

High-speed rail makes it easy and efficient to move around. It helps link cities and factories, integrating with other transportation systems as needed. Elm and Acadia are uniquely suitable for serving this role in modern web apps.

Elm and Acadia offer simple code with strong guarantees. No runtime errors, no aliasing bugs, limited invalid data, limited supply chain attacks, easy to refactor, helpful error messages, etc. The idea is to **write as much code as possible within this “fast path” and drop down into other languages as needed.**

```
       ┌────────────────────────┐
  ┌────┤                        │
  │ JS │                        ├───┐
  └────┤                        │ C │
       │       Elm/Acadia       ├───┘
       │                        ├────────┐
       │                        │ Erlang │
       │                        ├────────┘
       └────────────────────────┘
```

For 90% of your code, you get the simplicity and guarantees you expect from Elm, and for the 10% of cases that need something special, you pick the right tool for the job. Maybe you need mutation and no GC pauses for some high performance code. Maybe you need complex concurrency with immutability and per thread GC for some networking code. Maybe you need a formal proof certain functionality. Etc.

The claim here is that the vast majority of code needed for web apps can live on the fast path, and it is no problem to embed a JS web component or to make an HTTP request to a Rust server now and then!

> **Aside on file I/O**: File systems and databases are both methods of persisting data on disk. Normally databases are defined on top of file systems, but the reverse is also possible. Files are essentially a column of `Bytes`. Directories can be represented as a table of directory/contents relations. Etc.
>
> Acadia goes the database route. It gives us nice structured data, efficient access, and clear versioning policies. It is very much in the spirit of Elm and Acadia to pick a single coherent approach that results in simple code with strong guarantees.
>
> From there, [distributed file systems](https://en.wikipedia.org/wiki/Comparison_of_distributed_file_systems) like [Ceph](https://en.wikipedia.org/wiki/Ceph_(software)) can handle replication and recovery of practically unlimited amounts of data. These systems can usually be operated over HTTP, and can be ideal for storing images, PDFs, etc. Whatever bulk data you need for your application.
>
> But when it comes to POSIX file systems on a single machine, many languages do it better than Elm ever could. C makes it easy to use the exact bytes on disk without any allocation overhead at all. Scala uses their type system to give better guarantees about permissions and file handle leaks. Python makes it just plain simple. Drop down into those languages as needed. Write the whole server in those languages as needed. This entire point of “secure core” is to use the appropriate language at the appropriate time.
>
