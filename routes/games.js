const express = require("express");
const router = express.Router();

const { Game, validateGame } = require("../models/game");

router.get("/", async (req, res) => {
  // res.send(games);
  const games = await Game.find().select("-__v").sort("name");
  res.send(games);
});

router.get("/:id", async (req, res) => {
  const game = await Game.findById(req.params.id).select("-__v");
  if (!game)
    return res.status(404).send("Request game with the given id not found.");
  res.send(game);
});

router.post("/", async (req, res) => {
  const { error } = validateGame(req.body);
  if (error) return res.status(400).send(error.details[0].message);

  let game = new Game({
    name: req.body.name,
  });
  await game.save();

  res.send(game);
});

router.put("/:id", async (req, res) => {
  const { error } = validateGame(req.body);
  if (error) return res.status(400).send(error.details[0].message);

  const game = await Game.findByIdAndUpdate(
    req.params.id,
    { name: req.body.name },
    {
      new: true,
    }
  );

  if (!game)
    return res.status(404).send("The game with the given ID was not found.");

  res.send(game);
});

router.delete("/:id", async (req, res) => {
  const game = await Game.findByIdAndRemove(req.params.id);

  if (!game)
    return res.status(404).send("The game with the given ID was not found.");

  res.send(game);
});

module.exports = router;
