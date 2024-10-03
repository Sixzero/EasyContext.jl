
function init_conversation_context()
  sys_msg = SYSTEM_PROMPT(ChatSH)
  sys_msg *= workspace_format_description()
  sys_msg *= shell_format_description()
  sys_msg *= julia_format_description()
  conv_ctx = ConversationCTX_from_sysmsg(sys_msg=sys_msg)
  return conv_ctx
end
