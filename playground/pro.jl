using EasyContext: EasyContextCreator, EasyContextCreatorV2, EasyContextCreatorV3
using AISH: initialize_ai_state, process_question, main, start, SimpleContexter

# main(;contexter=SimpleContexter())
# main(;contexter=EasyContextCreatorV2())
main(;contexter=EasyContextCreatorV3())

