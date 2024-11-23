
export append_ctx_descriptors, reset_ctx_descriptors

function reset_ctx_descriptors(conv_ctx, system_prompt)
  conv_ctx.system_message.content = system_prompt
  conv_ctx
end

function append_ctx_descriptors(conv_ctx, args...)
  for arg in args
    conv_ctx.system_message.content *= arg
  end
  conv_ctx
end