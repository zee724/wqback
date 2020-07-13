const express = require("express");
const morgan = require("morgan");
const config = require("config");
const courses = require("./routes/courses");
const home = require("./routes/home");
const app = express();

app.use(express.json());

app.use("/api/courses", courses);
app.use("/", home);
// Configuration
console.log("Application Name: " + config.get("name"));
console.log("Mail Server: " + config.get("mail.host"));
// console.log("Mail Password: " + config.get("mail.password"));

if (app.get("env") === "development") {
  app.use(morgan("tiny"));
  console.log("Morgan enabled");
}

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`Listening on port ${port}...`));
