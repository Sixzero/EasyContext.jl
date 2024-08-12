expr2symbol(s::Symbol) = s
expr2symbol(expr::Expr) = Symbol("$expr")
function is_function_assignment(expr::Expr)
  return expr.head == :(=) && 
         (expr.args[1] isa Expr && expr.args[1].head == :call)
end

function get_function_name(expr::Expr)
  if expr.head == :function
    func_sig = expr.args[1]
    return expr2symbol(func_sig isa Symbol ? func_sig : func_sig.args[1])
  elseif is_function_assignment(expr)
    func_sig = expr.args[1]
    return expr2symbol(func_sig.args[1])
  else
      return :unknown
  end
end

function get_struct_name(expr::Expr)
  if expr.head == :struct
    return expr2symbol(expr.args[2])
  else
    return :unknown
  end
end

function get_expression_name(expr::Expr)
  if expr.head == :(=)
    return expr2symbol(expr.args[1])
  elseif expr.head == :const
    return get_expression_name(expr.args[1])
  elseif expr.head == :macrocall
    return get_expression_name(expr.args[end])
  else
      return :unknown
  end
end

# Additional helper function for safe substring
function safe_substring(s::AbstractString, i::Integer, j::Integer)
  start = clamp(i, 1, lastindex(s))
  stop = clamp(j, start, lastindex(s))
  return s[start:prevind(s, stop + 1)]
end