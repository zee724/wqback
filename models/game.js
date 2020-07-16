const mongoose = require("mongoose");
const Joi = require("joi");

const gameSchema = new mongoose.Schema({
  name: {
    type: String,
    required: true,
    minlength: 2,
    maxlength: 50,
  },
});

const Game = mongoose.model("Game", gameSchema);

function validateGame(game) {
  const schema = {
    name: Joi.string().min(3).required(),
  };
  return Joi.validate(game, schema);
}

exports.Game = Game;
exports.validateGame = validateGame;
