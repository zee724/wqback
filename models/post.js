const Joi = require("joi");
const mongoose = require("mongoose");

const postSchema = new mongoose.Schema({
  title: {
    type: String,
    required: true,
    minlength: 2,
    maxlength: 50,
  },
  content: {
    type: String,
    required: true,
  },
});

const Post = mongoose.model("Post", postSchema);

function validatePost(post) {
  const schema = Joi.object({
    title: Joi.string().min(2).max(50).required(),
    content: Joi.string().required(),
  });

  return schema.validate(post);
}

exports.Post = Post;
exports.validate = validatePost;
