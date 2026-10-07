///|
pub struct Server {
  port : Int
  host : String
  tags : Array[String]
  retries : Int?
}

///|
pub let server : Server = Server::{
  port: 8080,
  host: "localhost",
  tags: ["a", "b"],
  retries: None,
}
