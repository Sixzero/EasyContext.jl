export append_ctx_descriptors

function append_ctx_descriptors(conv_ctx, args...)
  for arg in args
    conv_ctx.system_message.content *= arg
  end
  conv_ctx
end