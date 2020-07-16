const config = require("config");
const mongoose = require("mongoose");

module.exports = async function () {
  const db = config.get("db");
  await mongoose.connect(db, {
    useNewUrlParser: true,
    useUnifiedTopology: true,
    useFindAndModify: false,
    useCreateIndex: true,
  });
};
