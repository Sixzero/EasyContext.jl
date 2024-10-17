export init_conversation_context, append_ctx_descriptors

function init_conversation_context(sys_msg)
  conv_ctx = ConversationX_from_sysmsg(;sys_msg)
  return conv_ctx
end
function append_ctx_descriptors(conv_ctx, args...)
  for arg in args
    conv_ctx.system_message.content *= arg
  end
  conv_ctx
end