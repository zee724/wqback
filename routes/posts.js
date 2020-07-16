const express = require("express");
const router = express.Router();

const { Post, validate } = require("../models/post");

router.get("/", async (req, res) => {
  // res.send(posts);
  const posts = await Post.find().select("-__v");
  res.send(posts);
});

router.get("/:id", async (req, res) => {
  const post = await Post.findById(req.params.id).select("-__v");
  if (!post)
    return res.status(404).send("Request post with the given id not found.");
  res.send(post);
});

router.post("/", async (req, res) => {
  const { error } = validate(req.body);
  if (error) return res.status(400).send(error.details[0].message);

  let post = new Post({
    title: req.body.title,
    content: req.body.content,
  });
  await post.save();

  res.send(post);
});

router.put("/:id", async (req, res) => {
  const { error } = validate(req.body);
  if (error) return res.status(400).send(error.details[0].message);

  const post = await Post.findByIdAndUpdate(
    req.params.id,
    { title: req.body.title, content: req.body.content },
    {
      new: true,
    }
  );

  if (!post)
    return res.status(404).send("The post with the given ID was not found.");

  res.send(post);
});

router.delete("/:id", async (req, res) => {
  const post = await Post.findByIdAndRemove(req.params.id);

  if (!post)
    return res.status(404).send("The post with the given ID was not found.");

  res.send(post);
});

module.exports = router;
