
function init_conversation_context(sys_ms, args...)
  for arg in args
    sys_ms *= arg
  end
  conv_ctx = Conversation_from_sysmsg(sys_msg=sys_ms)
  return conv_ctx
end
