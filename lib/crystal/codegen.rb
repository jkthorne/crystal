require 'llvm/core'
require 'llvm/execution_engine'
require 'llvm/transforms/scalar'
require_relative "program"

LLVM.init_x86

module Crystal
  class Program
    def run(code, options = {})
      node = parse code
      node = normalize node
      infer_type node, options
      evaluate node
    end

    def evaluate(node)
      llvm_mod = build node
      engine = LLVM::JITCompiler.new(llvm_mod)
      Compiler.optimize llvm_mod, engine, 1
      engine.run_function llvm_mod.functions["crystal_main"], 0, nil
    end

    def build(node, filename = nil, debug = false, llvm_mod = nil)
      visitor = CodeGenVisitor.new(self, node, node ? node.type : nil, filename, debug, llvm_mod)
      if node
        begin
          node.accept visitor
        rescue StandardError => ex
          visitor.llvm_mod.dump
          raise
        end
      end

      visitor.finish
      visitor.llvm_mod.dump if Crystal::DUMP_LLVM
      visitor.llvm_mod.verify!
      visitor.llvm_mod
    end
  end

  class CodeGenVisitor < Visitor
    attr_reader :llvm_mod
    attr_reader :current_node

    def initialize(mod, node, return_type, filename = nil, debug = false, llvm_mod = nil)
      @filename = filename
      @debug = debug
      @mod = mod
      @node = node
      @ints = {}
      @ints_1 = {}
      @ints_8 = {}
      @return_type = return_type && return_type.union? ? nil : return_type
      @llvm_mod = llvm_mod || LLVM::Module.new("Crystal")
      @fun = @llvm_mod.functions.add("crystal_main", [LLVM::Int, LLVM::Pointer(LLVM::Pointer(LLVM::Int8))], @return_type ? @return_type.llvm_type : LLVM.Void)

      @argc = @fun.params[0]
      @argc.name = 'argc'

      @argv = @fun.params[1]
      @argv.name = 'argv'

      @builder = LLVM::Builder.new
      @builder = DebugLLVMBuilder.new @builder, self if debug
      @builder = CrystalLLVMBuilder.new @builder

      @alloca_block, @const_block, @entry_block = new_entry_block_chain "alloca", "const", "entry"
      @const_block_entry = @const_block

      @vars = {}
      @block_context = []
      @type = @mod

      @strings = {}
      @symbols = {}
      symbol_table_values = []
      mod.symbols.to_a.sort.each_with_index do |sym, index|
        @symbols[sym] = index
        symbol_table_values << build_string_constant(sym, sym)
      end

      symbol_table = @llvm_mod.globals.add(LLVM::Array(mod.string.llvm_type, symbol_table_values.count), "symbol_table")
      symbol_table.linkage = :internal
      symbol_table.initializer = LLVM::ConstantArray.const(mod.string.llvm_type, symbol_table_values)

      @union_maps = {}
      @is_a_maps = {}

      if debug
        @empty_md_list = metadata(metadata(0))
        @subprograms = [fun_metadata(@fun, "crystal_main", @filename, 1)]
      end
    end

    def int(n)
      @ints[n] ||= LLVM::Int(n)
    end

    def int1(n)
      @ints_1[n] ||= LLVM::Int1.from_i(n)
    end

    def int8(n)
      @ints_8[n] ||= LLVM::Int8.from_i(n)
    end

    def main
      @fun
    end

    def finish
      br_block_chain @alloca_block, @const_block_entry
      br_block_chain @const_block, @entry_block
      @builder.ret(@return_type ? @last : nil)

      add_compile_unit_metadata @filename if @debug
    end

    def visit_any(node)
      @current_node = node
    end

    def accept(node)
      old_current_node = @current_node
      node.accept self
      @current_node = old_current_node
    end

    def visit_nil_literal(node)
      @last = llvm_nil
    end

    def visit_bool_literal(node)
      @last = int1(node.value ? 1 : 0)
    end

    def visit_int_literal(node)
      @last = int(node.value.to_i)
    end

    def visit_long_literal(node)
      @last = LLVM::Int64.from_i(node.value.to_i)
    end

    def visit_float_literal(node)
      @last = LLVM::Float.parse(node.type.llvm_type, node.value)
    end

    def visit_double_literal(node)
      @last = LLVM::Double.parse(node.type.llvm_type, node.value)
    end

    def visit_char_literal(node)
      @last = int8(node.value)
    end

    def visit_string_literal(node)
      @last = build_string_constant(node.value)
    end

    def build_string_constant(str, name = "str")
      name = name.gsub('@', '.')
      unless string = @strings[str]
        global = @llvm_mod.globals.add(LLVM.Array(LLVM::Int8, str.length + 5), name)
        global.linkage = :private
        global.global_constant = 1
        bytes = "#{[str.length].pack("l")}#{str}\0".chars.to_a.map { |c| int8(c.ord) }
        global.initializer = LLVM::ConstantArray.const(LLVM::Int8, bytes)
        @strings[str] = string = @builder.bit_cast(global, @mod.string.llvm_type)
      end
      string
    end

    def visit_symbol_literal(node)
      @last = int(@symbols[node.value])
    end

    def visit_range_literal(node)
      accept(node.expanded)
      false
    end

    def visit_regexp_literal(node)
      accept(node.expanded)
    end

    def visit_hash_literal(node)
      accept(node.expanded)
      false
    end

    def visit_class_method(node)
      @last = int(0)
    end

    def visit_expressions(node)
      node.expressions.each do |exp|
        accept(exp)
        break if exp.returns? || exp.breaks? || (exp.yields? && (block_returns? || block_breaks?))
      end
      false
    end

    def end_visit_return(node)
      if @return_block
        if @return_type.union?
          assign_to_union(@return_union, @return_type, node.exps[0].type, @last)
          @last = @builder.load @return_union
        end
        @return_block_table[@builder.insert_block] = @last
        @builder.br @return_block
      elsif @return_type.union?
        assign_to_union(@return_union, @return_type, node.exps[0].type, @last)
        union = @builder.load @return_union
        @builder.ret union
      elsif @return_type.nilable?
        if @last.type.kind == :integer
          @builder.ret @builder.int2ptr(@last, @return_type.llvm_type)
        else
          @builder.ret @last
        end
      else
        @builder.ret @last
      end
    end

    def visit_lib_def(node)
      false
    end

    def visit_ident(node)
      const = node.target_const
      if const
        global_name = const.to_s
        global = @llvm_mod.globals[global_name]

        unless global
          global = @llvm_mod.globals.add(const.value.type.llvm_type, global_name)
          global.linkage = :internal

          old_position = @builder.insert_block
          old_fun = @fun
          @fun = @llvm_mod.functions["crystal_main"]
          const_block = new_block "const_#{global_name}"
          @builder.position_at_end const_block

          accept(const.value)

          if @last.constant?
            global.initializer = @last
            global.global_constant = 1
          else
            global.initializer = LLVM::Constant.null(@last.type)
            @builder.store @last, global
          end

          new_const_block = @builder.insert_block
          @builder.position_at_end @const_block
          @builder.br const_block
          @const_block = new_const_block

          @builder.position_at_end old_position
          @fun = old_fun
        end

        @last = @builder.load global
      else
        @last = int(0)
      end
    end

    def visit_assign(node)
      codegen_assign_node(node.target, node.value)
    end

    def visit_multi_assign(node)
      llvm_values = []

      node.targets.each_with_index do |target, i|
        if target.is_a?(Ident)
          llvm_values << nil
        else
          accept(node.values[i])
          llvm_values << @last
        end
      end

      node.targets.each_with_index do |target, i|
        llvm_value = llvm_values[i]
        if llvm_value
          codegen_assign_target(target, node.values[i], llvm_value)
        end
      end

      @last = llvm_nil

      false
    end

    def codegen_assign_node(target, value)
      if target.is_a?(Ident)
        return false
      end

      accept(value)

      codegen_assign_target(target, value, @last)

      false
    end

    def codegen_assign_target(target, value, llvm_value)
      case target
      when InstanceVar
        ivar = @type.lookup_instance_var(target.name.to_s)
        ptr = gep llvm_self_ptr, 0, @type.index_of_instance_var(target.name.to_s)
      when Global
        ptr = @llvm_mod.globals[target.name.to_s]
        unless ptr
          ptr = @llvm_mod.globals.add(target.llvm_type, target.name.to_s)
          ptr.linkage = :internal
          ptr.initializer = LLVM::Constant.null(target.llvm_type)
        end
      else
        var = declare_var(target)
        ptr = var[:ptr]
      end

      codegen_assign(ptr, target.type, value.type, llvm_value)
    end

    def declare_var(var)
      llvm_var = @vars[var.name.to_s]
      unless llvm_var
        llvm_var = @vars[var.name.to_s] = {
          ptr: alloca(var.llvm_type, var.name.to_s),
          type: var.type
        }
        if var.type.is_a?(UnionType) && union_type_id = var.type.types.any?(&:nil_type?)
          in_alloca_block { assign_to_union(llvm_var[:ptr], var.type, @mod.nil, llvm_nil) }
        end
      end
      llvm_var
    end

    def visit_var(node)
      var = @vars[node.name]
      if var[:type] == node.type
        @last = var[:ptr]
        @last = @builder.load(@last, node.name) unless (var[:treated_as_pointer] || var[:type].union?)
      elsif var[:type].nilable?
        if node.type.nil_type?
          @last = null_pointer?(var[:ptr])
        else
          @last = var[:ptr]
          @last = @builder.load(@last, node.name) unless (var[:treated_as_pointer] || var[:type].union?)
        end
      else
        if node.type.union?
          @last = @builder.bit_cast(var[:ptr], LLVM::Pointer(node.llvm_type))
        else
          value_ptr = union_value(var[:ptr])
          @last = @builder.bit_cast value_ptr, LLVM::Pointer(node.llvm_type)
          @last = @builder.load(@last) unless node.type.passed_by_val?
        end
      end
    end

    def visit_casted_var(node)
      var = @vars[node.name]
      if var[:type] == node.type
        @last = var[:ptr]
        @last = @builder.load(@last, node.name) unless (var[:treated_as_pointer] || var[:type].union?)
      elsif var[:type].nilable?
        if node.type.nil_type?
          @last = null_pointer?(var[:ptr])
        elsif node.type.equal?(@mod.object)
          @last = @builder.bit_cast var[:ptr], @mod.object.llvm_type
        elsif node.type.equal?(@mod.object.hierarchy_type)
          @last = box_object_in_hierarchy(var[:type], node.type, var[:ptr], !var[:treated_as_pointer])
        else
          @last = var[:ptr]
          @last = @builder.load(@last, node.name) unless (var[:treated_as_pointer] || var[:type].union?)
          if node.type.hierarchy?
            @last = box_object_in_hierarchy(var[:type].nilable_type, node.type, @last, !var[:treated_as_pointer])
          end
        end
      elsif node.type.union?
        @last = @builder.bit_cast var[:ptr], LLVM::Pointer(node.llvm_type)
      else
        value_ptr = union_value(var[:ptr])
        casted_value_ptr = @builder.bit_cast value_ptr, LLVM::Pointer(node.llvm_type)
        @last = @builder.load(casted_value_ptr)
      end
    end

    def visit_global(node)
      if @mod.global_vars[node.name].type.union?
        @last = @llvm_mod.globals[node.name]
      else
        @last = @builder.load @llvm_mod.globals[node.name]
      end
    end

    def visit_instance_var(node)
      ivar = @type.lookup_instance_var(node.name)
      if ivar.type.union?
        @last = gep llvm_self_ptr, 0, @type.index_of_instance_var(node.name)
      else
        index = @type.index_of_instance_var(node.name)
        struct = @builder.load llvm_self_ptr
        @last = @builder.extract_value struct, index, node.name
      end
    end

    def visit_is_a(node)
      accept(node.obj)

      obj_type = node.obj.type
      const_type = node.const.type.instance_type

      if obj_type.is_a?(UnionType)
        matching_ids = obj_type.types.select { |t| t.implements?(const_type) }.map { |t| int(t.type_id) }

        case matching_ids.length
        when 0
          @last = int1(0)
        when obj_type.types.count
          @last = int1(1)
        else
          type_id = @builder.load union_type_id(@last)

          result = nil
          matching_ids.each do |matching_id|
            cmp = @builder.icmp :eq, type_id, matching_id
            result = result ? @builder.or(result, cmp) : cmp
          end

          @last = result
        end
      elsif obj_type.is_a?(HierarchyType)
        is_a = obj_type.base_type.implements?(const_type)
        @last = int1(is_a ? 1 : 0)
      elsif obj_type.nilable?
        if const_type.nil_type?
          @last = null_pointer?(@last)
        elsif obj_type.types.any? { |t| t.implements?(const_type) }
          @last = not_null_pointer?(@last)
        else
          @last = int1(0)
        end
      else
        is_a = obj_type.implements?(const_type)
        @last = int1(is_a ? 1 : 0)
      end

      false
    end

    def visit_pointer_of(node)
      if node.var.is_a?(Var)
        var = @vars[node.var.name]
        @last = var[:ptr]
      else
        var = @type.lookup_instance_var(node.var.name)
        @last = gep llvm_self_ptr, 0, @type.index_of_instance_var(node.var.name)
      end
      if node.type.var.type.is_a?(StructType)
        @last = @builder.load @last
      end
      false
    end

    def visit_pointer_malloc(node)
      @last = @builder.array_malloc(node.type.var.llvm_type, @vars['size'][:ptr])
    end

    def visit_pointer_realloc(node)
      casted_ptr = @builder.bit_cast llvm_self, LLVM::Pointer(LLVM::Int8)
      size = @vars['size'][:ptr]
      size = @builder.mul size, int(@type.var.type.llvm_size)
      reallocated_ptr = realloc casted_ptr, size
      @last = @builder.bit_cast reallocated_ptr, LLVM::Pointer(@type.var.llvm_type)
    end

    def visit_pointer_get_value(node)
      if @type.var.type.union? || @type.var.type.is_a?(StructType)
        @last = llvm_self
      else
        @last = @builder.load llvm_self
      end
    end

    def visit_pointer_set_value(node)
      value = @fun.params[1]
      if node.type.union?
        value = @builder.alloca node.llvm_type
        target = @fun.params[1]
        target = @builder.load(target) if node.type.passed_by_val?
        @builder.store target, value
      end

      codegen_assign llvm_self, @type.var.type, node.type, value
      @last = value
    end

    def visit_pointer_add(node)
      @last = gep(llvm_self, @fun.params[1])
    end

    def visit_pointer_cast(node)
      @last = @builder.bit_cast(@fun.params[0], node.type.llvm_type)
    end

    def visit_simple_or(node)
      node.left.accept self
      left = codegen_cond(node.left)

      node.right.accept self
      right = codegen_cond(node.right)

      @last = @builder.or left, right
      false
    end

    def visit_if(node)
      is_union = node.type && node.type.union?
      is_nilable = node.type && node.type.nilable?
      union_ptr = alloca node.llvm_type if is_union

      const_value = check_const(node.cond)
      case const_value
      when true
        node.else = node.then # So if the then returns, also the whole if

        if node.then
          accept(node.then)
        else
          @last = llvm_nil
        end

        if is_union && (!node.then || node.then.type)
          codegen_assign(union_ptr, node.type, node.then ? node.then.type : @mod.nil, @last)
          @last = union_ptr
        elsif is_nilable && @last.type.kind == :integer
          @last = @builder.int2ptr @last, node.llvm_type
        end

        return false
      when false
        node.then = node.else # So if the else returns, also the whole if

        if node.else
          accept(node.else)
        else
          @last = llvm_nil
        end

        if is_union && (!node.else || node.else.type)
          codegen_assign(union_ptr, node.type, node.else ? node.else.type : @mod.nil, @last)
          @last = union_ptr
        elsif is_nilable && @last.type.kind == :integer
          @last = @builder.int2ptr @last, node.llvm_type
        end

        return false
      end

      then_block, else_block, exit_block = new_blocks "then", "else", "exit"

      codegen_cond_branch(node.cond, then_block,else_block)

      @builder.position_at_end then_block
      if node.then
        accept(node.then)
        then_block = @builder.insert_block
      end
      if node.then.nil? || node.then.type.nil? || node.then.type.nil_type?
        if is_nilable
          @last = @builder.int2ptr llvm_nil, node.llvm_type
        else
          @last = llvm_nil
        end
      end
      then_value = @last unless node.then && (node.then.returns? || node.then.breaks? || (node.then.yields? && block_returns?))
      codegen_assign(union_ptr, node.type, node.then ? node.then.type : @mod.nil, @last) if is_union && (!node.then || node.then.type)
      @builder.br exit_block

      @builder.position_at_end else_block
      if node.else
        accept(node.else)
        else_block = @builder.insert_block
      end
      if node.else.nil? || node.else.type.nil? || node.else.type.nil_type?
        if is_nilable
          @last = @builder.int2ptr llvm_nil, node.llvm_type
        else
          @last = llvm_nil
        end
      end
      else_value = @last unless node.else && (node.else.returns? || node.else.breaks? || (node.else.yields? && block_returns?))
      codegen_assign(union_ptr, node.type, node.else ? node.else.type : @mod.nil, @last) if is_union && (!node.else || node.else.type)
      @builder.br exit_block

      @builder.position_at_end exit_block

      if is_union
        @last = union_ptr
      elsif node.type
        if then_value && else_value
          @last = @builder.phi node.llvm_type, {then_block => then_value, else_block => else_value}
        elsif then_value
          @last = then_value
        elsif else_value
          @last = else_value
        end
      else
        if node.then && !then_value && node.else && !else_value
          @builder.unreachable
        end
        @last = nil
      end

      false
    end

    def visit_while(node)
      while_block, body_block, exit_block = new_blocks "while", "body", "exit"

      @builder.br node.run_once ? body_block : while_block

      @builder.position_at_end while_block

      accept(node.cond)
      codegen_cond_branch(node.cond, body_block, exit_block)

      @builder.position_at_end body_block
      old_while_exit_block = @while_exit_block
      @while_exit_block = exit_block
      accept(node.body) if node.body
      @while_exit_block = old_while_exit_block
      @builder.br while_block

      @builder.position_at_end exit_block
      @builder.unreachable if node.body && node.body.yields? && block_breaks?

      @last = llvm_nil

      false
    end

    def check_const(node_cond)
      accept(node_cond)

      if @mod.nil == node_cond.type
        return false
      elsif @mod.bool == node_cond.type
        # Nothing
      elsif node_cond.type.nilable?
        # Nothing
      elsif node_cond.type.is_a?(UnionType)
        nil_or_bool = node_cond.type.types.any? { |t| t.nil_type? || t.equal?(@mod.bool) }
        return true unless nil_or_bool
      elsif node_cond.type.is_a?(PointerType)
        # Nothing
      else
        return true
      end

      if @last.constant?
        if @last == int1(0)
          return false
        elsif @last == int1(1)
          return true
        end
      end

      nil
    end

    def codegen_cond_branch(node_cond, then_block, else_block)
      @builder.cond(codegen_cond(node_cond), then_block, else_block)

      nil
    end

    def codegen_cond(node_cond)
      if @mod.nil.equal?(node_cond.type)
        cond = int1(0)
      elsif @mod.bool.equal?(node_cond.type)
        cond = @builder.icmp :ne, @last, int1(0)
      elsif node_cond.type.nilable?
        cond = not_null_pointer?(@last)
      elsif node_cond.type.union?
        has_nil = node_cond.type.types.any?(&:nil_type?)
        has_bool = node_cond.type.types.any? { |t| t.equal?(@mod.bool) }

        if has_nil || has_bool
          type_id = @builder.load union_type_id(@last)
          value = @builder.load(@builder.bit_cast union_value(@last), LLVM::Pointer(LLVM::Int1))

          is_nil = @builder.icmp :eq, type_id, int(@mod.nil.type_id)
          is_bool = @builder.icmp :eq, type_id, int(@mod.bool.type_id)
          is_false = @builder.icmp(:eq, value, int1(0))
          cond = @builder.not(@builder.or(is_nil, @builder.and(is_bool, is_false)))
        elsif has_nil
          type_id = @builder.load union_type_id(@last)
          cond = @builder.icmp :ne, type_id, int(@mod.nil.type_id)
        elsif has_bool
          type_id = @builder.load union_type_id(@last)
          value = @builder.load(@builder.bit_cast union_value(@last), LLVM::Pointer(LLVM::Int1))

          is_bool = @builder.icmp :eq, type_id, int(@mod.bool.type_id)
          is_false = @builder.icmp(:eq, value, int1(0))
          cond = @builder.not(@builder.and(is_bool, is_false))
        else
          cond = int1(1)
        end
      elsif node_cond.type.is_a?(PointerType)
        cond = not_null_pointer?(@last)
      else
        cond = int1(1)
      end
    end

    def end_visit_break(node)
      if @break_type && @break_type.union?
        if node.exps.length > 0
          assign_to_union(@break_union, @break_type, node.exps[0].type, @last)
        else
          assign_to_union(@break_union, @break_type, @mod.nil, llvm_nil)
        end
      elsif @break_table
        if @break_type.nilable? && node.exps.empty?
          @break_table[@builder.insert_block] = @builder.int2ptr llvm_nil, @break_type.llvm_type
        else
          @break_table[@builder.insert_block] = @last
        end
      end
      @builder.br @while_exit_block
    end

    def block_returns?
      return false if @block_context.empty?

      context = @block_context.pop
      breaks = context && (context[:block].returns? || (context[:block].yields? && block_returns?))
      @block_context.push context
      breaks
    end

    def block_breaks?
      return false if @block_context.empty?

      context = @block_context.pop
      breaks = context && (context[:block].breaks? || (context[:block].yields? && block_breaks?))
      @block_context.push context
      breaks
    end

    def visit_def(node)
      false
    end

    def visit_macro(node)
      false
    end

    def visit_class_def(node)
      false
    end

    def visit_struct_def(node)
      false
    end

    def visit_include(node)
      false
    end

    def visit_case(node)
      accept(node.expanded)
      false
    end

    def visit_primitive_body(node)
      @last = node.block.call(@builder, @fun, @llvm_mod, @type)
    end

    def visit_allocate(node)
      @last = malloc node.type.llvm_struct_type
      memset @last, int8(0), node.type.llvm_struct_type.size
      @last
    end

    def visit_struct_alloc(node)
      @last = malloc node.type.llvm_struct_type
      memset @last, int8(0), node.type.llvm_struct_type.size
      @last
    end

    def visit_struct_get(node)
      index = @type.index_of_var(node.name)
      struct = @builder.load llvm_self
      @last = @builder.extract_value struct, index, node.name
    end

    def visit_struct_set(node)
      ptr = gep llvm_self, 0, @type.index_of_var(node.name)
      @last = @vars['value'][:ptr]
      @builder.store @last, ptr
    end

    def visit_array_literal(node)
      accept(node.expanded)
      false
    end

    def visit_argc(node)
      @last = @argc
    end

    def visit_argv(node)
      @last = @argv
    end

    def visit_nil_pointer(node)
      @last = LLVM::Constant.null(node.llvm_type)
    end

    def visit_call(node)
      if node.target_macro
        accept(node.target_macro)
        return false
      end

      if node.target_defs && node.target_defs.length > 1
        codegen_dispatch(node)
        return false
      end

      declare_out_arguments(node) if node.target_defs

      if !node.target_defs || node.target_def.owner.is_subclass_of?(@mod.value)
        owner = ((node.obj && node.obj.type) || node.scope)
      else
        owner = node.target_def.owner
      end
      owner = nil unless owner.passed_as_self?

      call_args = []
      if node.obj && node.obj.type.passed_as_self?
        accept(node.obj)

        if node.obj.type.class? && !node.obj.type.equal?(node.target_def.owner)
          if node.target_def.owner.hierarchy?
            @last = box_object_in_hierarchy(node.obj.type, node.target_def.owner, @last, false)
          else
            # Cast value
            @last = @builder.bit_cast(@last, LLVM::Pointer(node.target_def.owner.llvm_type))
            # TODO: why is this load needed here but not if we don't enter this case?
            @last = @builder.load(@last)
          end
        end

        call_args << @last
      elsif owner
        different = !owner.equal?(@vars['self'][:type])
        if different && owner.hierarchy? && @vars['self'][:type].class?
          call_args << box_object_in_hierarchy(@vars['self'][:type], owner, llvm_self, false)
        elsif different && owner.class?
          if @vars['self'][:type].hierarchy?
            call_args << llvm_self_ptr
          else
            call_args << @builder.bit_cast(llvm_self, owner.llvm_type)
          end
        else
          call_args << llvm_self
        end
      end

      node.args.each_with_index do |arg, i|
        if node.target_defs && node.target_def.args[i] && node.target_def.args[i].out && arg.is_a?(Var)
          call_args << @vars[arg.name][:ptr]
        else
          accept(arg)
          call_args << @last
        end
      end

      return if node.args.any?(&:yields?) && block_breaks?

      if node.block
        @block_context << { block: node.block, vars: @vars, type: @type,
          return_block: @return_block, return_block_table: @return_block_table,
          return_type: @return_type, return_union: @return_union }
        @vars = {}

        if owner && owner.passed_as_self?
          @type = owner
          args_base_index = 1
          if owner.union?
            ptr = alloca(owner.llvm_type)
            value = call_args[0]
            value = @builder.load(value) if owner.passed_by_val?
            @builder.store value, ptr
            @vars['self'] = { ptr: ptr, type: owner, treated_as_pointer: false }
          else
            @vars['self'] = { ptr: call_args[0], type: owner, treated_as_pointer: true }
          end
        else
          args_base_index = 0
        end

        node.target_def.args.each_with_index do |arg, i|
          ptr = alloca(arg.llvm_type, arg.name)
          @vars[arg.name] = { ptr: ptr, type: arg.type }
          value = call_args[args_base_index + i]
          value = @builder.load(value) if arg.type.passed_by_val?
          @builder.store value, ptr
        end

        @return_block = new_block 'return'
        @return_block_table = {}
        @return_type = node.type
        if @return_type.union?
          @return_union = alloca(node.llvm_type, 'return')
        else
          @return_union = nil
        end
        accept(node.target_def.body)
        if node.target_def.body.type && !node.target_def.body.type.nil_type? && !node.block.breaks?
          if @return_union
            assign_to_union(@return_union, @return_type, node.target_def.body.type, @last)
          else
            @return_block_table[@builder.insert_block] = @last
          end
        elsif (node.target_def.body.type.nil? || node.target_def.body.type.nil_type?) && node.type.nilable?
          @return_block_table[@builder.insert_block] = @builder.int2ptr llvm_nil, node.llvm_type
        end
        @builder.br @return_block
        @builder.position_at_end @return_block

        if node.returns? || block_returns? || (node.block.yields? && block_breaks?)
          @builder.unreachable
        else
          if node.type && !node.type.nil_type?
            if @return_union
              @last = @return_union
            else
              phi_type = node.type.llvm_type
              phi_type = LLVM::Pointer(phi_type) if node.type.union?
              @last = @builder.phi phi_type, @return_block_table
            end
          end
        end

        old_context = @block_context.pop
        @vars = old_context[:vars]
        @type = old_context[:type]
        @return_block = old_context[:return_block]
        @return_block_table = old_context[:return_block_table]
        @return_type = old_context[:return_type]
        @return_union = old_context[:return_union]
      else
        old_return_block = @return_block
        old_return_block_table = @return_block_table
        old_break_table = @break_table
        @return_block = @return_block_table = @break_table = nil

        codegen_call(node.target_def, owner, call_args)

        @return_block = old_return_block
        @return_block_table = old_return_block_table
        @break_table = old_break_table
      end

      false
    end

    def box_object_in_hierarchy(object, hierarchy, value, load = true)
      hierarchy_type = alloca hierarchy.llvm_type
      type_id_ptr, value_ptr = union_type_id_and_value(hierarchy_type)
      @builder.store int(object.type_id), type_id_ptr
      @builder.store @builder.bit_cast(value, LLVM::Pointer(LLVM::Int8)), value_ptr
      if load
        @builder.load(hierarchy_type)
      else
        hierarchy_type
      end
    end

    def declare_out_arguments(call)
      return unless call.target_def.is_a?(External)

      call.target_def.args.each_with_index do |arg, i|
        if arg.out
          var = call.args[i]
          declare_var(var) if var.is_a?(Var)
        end
      end
    end

    def visit_yield(node)
      if @block_context.any?
        context = @block_context.pop
        new_vars = context[:vars].clone
        block = context[:block]

        block.args.each_with_index do |arg, i|
          exp = node.exps[i]
          if exp
            exp_type = exp.type
            exp.accept self
          else
            exp_type = @mod.nil
            @last = llvm_nil
          end

          copy = alloca exp_type.llvm_type, "block_#{arg.name}"
          codegen_assign copy, exp_type, exp_type, @last
          new_vars[arg.name] = { ptr: copy, type: arg.type }
        end

        old_vars = @vars
        old_type = @type
        old_return_block = @return_block
        old_return_block_table = @return_block_table
        old_return_type = @return_type
        old_return_union = @return_union
        old_while_exit_block = @while_exit_block
        old_break_table = @break_table
        old_break_type = @break_type
        old_break_union = @break_union
        @while_exit_block = @return_block
        @break_table = @return_block_table
        @break_type = @return_type
        @break_union = @return_union
        @vars = new_vars
        @type = context[:type]
        @return_block = context[:return_block]
        @return_block_table = context[:return_block_table]
        @return_type = context[:return_type]
        @return_union = context[:return_union]

        accept(block)

        @last = llvm_nil unless node.type

        @while_exit_block = old_while_exit_block
        @break_table = old_break_table
        @break_type = old_break_type
        @break_union = old_break_union
        @vars = old_vars
        @type = old_type
        @return_block = old_return_block
        @return_block_table = old_return_block_table
        @return_type = old_return_type
        @return_union = old_return_union
        @block_context << context
      end
      false
    end

    def codegen_call(target_def, self_type, call_args)
      mangled_name = target_def.mangled_name(self_type)

      unless fun = @llvm_mod.functions[mangled_name]
        old_current_node = @current_node
        old_fun = @fun
        @current_node = target_def
        codegen_fun(mangled_name, target_def, self_type)
        @current_node = old_current_node
        fun = @fun
        @fun = old_fun
      end

      @last = @builder.call fun, *call_args

      if target_def.type.union?
        union = alloca target_def.llvm_type
        @builder.store @last, union
        @last = union
      end
    end

    def codegen_fun(mangled_name, target_def, self_type)
      old_position = @builder.insert_block
      old_vars = @vars
      old_type = @type
      old_entry_block = @entry_block
      old_alloca_block = @alloca_block

      @vars = {}

      args = []
      if self_type && self_type.passed_as_self?
        @type = self_type
        args << Var.new("self", self_type)
      end
      args += target_def.args

      varargs = target_def.is_a?(External) && target_def.varargs

      @fun = @llvm_mod.functions.add(
        mangled_name,
        args.map(&:llvm_arg_type),
        target_def.llvm_type,
        varargs: varargs
      )
      @subprograms << def_metadata(@fun, target_def) if @debug

      args.each_with_index do |arg, i|
        @fun.params[i].name = arg.name
        @fun.params[i].add_attribute :by_val_attribute if arg.type.passed_by_val?
      end

      unless target_def.is_a? External
        @fun.linkage = :internal
        new_entry_block

        args.each_with_index do |arg, i|
          if (self_type && i == 0 && !self_type.union?) || target_def.body.is_a?(Primitive) || arg.type.passed_by_val?
            @vars[arg.name] = { ptr: @fun.params[i], type: arg.type, treated_as_pointer: true }
          else
            ptr = alloca(arg.llvm_type, arg.name)
            @vars[arg.name] = { ptr: ptr, type: arg.type }
            @builder.store @fun.params[i], ptr
          end
        end

        if target_def.body
          old_return_type = @return_type
          old_return_union = @return_union
          @return_type = target_def.type
          @return_union = alloca(target_def.llvm_type, 'return') if @return_type.union?

          accept(target_def.body)

          if @return_type.union?
            if target_def.body.type != @return_type && !target_def.body.returns?
              assign_to_union(@return_union, @return_type, target_def.body.type, @last)
              @last = @builder.load @return_union
            else
              @last = @builder.load @last
            end
          end

          if @return_type.nilable? && target_def.body.type.nil_type?
            @builder.ret LLVM::Constant.null(@return_type.llvm_type)
          else
            @builder.ret(@last)
          end

          @return_type = old_return_type
          @return_union = old_return_union
        else
          @builder.ret llvm_nil
        end

        br_from_alloca_to_entry

        @builder.position_at_end old_position
      end

      @vars = old_vars
      @type = old_type
      @entry_block = old_entry_block
      @alloca_block = old_alloca_block
    end

    def match_any_type_id(type, type_id)
      # Special case: if the type is Object+ we want to match against Reference+,
      # because Object+ can only mean a Reference type (so we exclude Nil, for example).
      type = @mod.reference.hierarchy_type if type.equal?(@mod.object.hierarchy_type)

      if type.union?
        result = int1(0)
        type.each do |sub_type|
          result = @builder.or(result, @builder.icmp(:eq, int(sub_type.type_id), type_id))
        end
        result
      else
        result = @builder.icmp :eq, int(type.type_id), type_id
      end
    end

    def codegen_dispatch(node)
      old_block = @builder.insert_block

      exit_block = new_block "exit"

      if node.obj
        owner = node.obj.type
        node.obj.accept(self)

        if owner.union?
          obj_type_id = @builder.load union_type_id(@last)
        elsif owner.nilable?
          obj_type_id = @last
        end
      else
        owner = node.scope

        if owner.equal?(@mod.program)
          # Nothing
        elsif owner.union?
          obj_type_id = @builder.load union_type_id(llvm_self)
        else
          obj_type_id = llvm_self
        end
      end

      phi_table = {}
      call = Call.new(node.obj ? CastedVar.new("%self") : nil, node.name, node.args.length.times.map { |i| CastedVar.new("%arg#{i}") }, node.block)
      call.scope = node.scope

      new_vars = @vars.clone

      if node.obj && node.obj.type.passed_as_self?
        new_vars['%self'] = { ptr: @last, type: node.obj.type, treated_as_pointer: true }
      end

      arg_type_ids = []
      node.args.each_with_index do |arg, i|
        arg.accept self
        if arg.type.union?
          arg_type_ids[i] = @builder.load union_type_id(@last)
        elsif arg.type.nilable?
          arg_type_ids[i] = @last
        end
        new_vars["%arg#{i}"] = { ptr: @last, type: arg.type, treated_as_pointer: true }
      end

      old_vars = @vars
      @vars = new_vars

      next_def_label = nil
      node.target_defs.each do |a_def|
        if owner.union?
            result = match_any_type_id(a_def.owner, obj_type_id)
        elsif owner.nilable?
          if a_def.owner.nil_type?
            result = null_pointer?(obj_type_id)
          else
            result = not_null_pointer?(obj_type_id)
          end
        else
          result = int1(1)
        end

        a_def.args.each_with_index do |arg, i|
          if node.args[i].type.union?
            comp = match_any_type_id(arg.type, arg_type_ids[i])
            result = @builder.and(result, comp)
          elsif node.args[i].type.nilable?
            if arg.type.nil_type?
              result = @builder.and(result, null_pointer?(arg_type_ids[i]))
            else
              result = @builder.and(result, not_null_pointer?(arg_type_ids[i]))
            end
          end
        end

        current_def_label, next_def_label = new_blocks "current_def", "next_def"
        @builder.cond result, current_def_label, next_def_label

        @builder.position_at_end current_def_label

        allocated = a_def.owner.allocated && a_def.args.all? { |arg| arg.type.allocated }
        if allocated
          call.obj.set_type(a_def.owner) if call.obj
          call.target_defs = [a_def]
          call.args.each_with_index do |arg, i|
            arg.set_type(a_def.args[i].type)
          end
          call.set_type node.type
          call.accept self

          unless call.returns?
            if node.type.union?
              phi_value = alloca node.llvm_type
              assign_to_union(phi_value, node.type, a_def.type, @last)
              phi_table[@builder.insert_block] = phi_value
            elsif node.type.nilable? && @last.type.kind == :integer
              phi_table[@builder.insert_block] = @builder.int2ptr @last, node.llvm_type
            else
              phi_table[@builder.insert_block] = @last
            end
          end

          @builder.br exit_block
        else
          @builder.unreachable
        end

        @builder.position_at_end next_def_label
      end

      @builder.unreachable

      @builder.position_at_end exit_block
      if node.returns?
        @builder.unreachable
      else
        if node.type.union?
          @last = @builder.phi LLVM::Pointer(node.llvm_type), phi_table
        else
          @last = @builder.phi node.llvm_type, phi_table
        end
      end

      @vars = old_vars
    end

    def codegen_assign(pointer, target_type, value_type, value)
      if target_type == value_type
        if target_type.union?
          value = @builder.load value
          @builder.store value, pointer
        else
          @builder.store value, pointer
        end
      else
        assign_to_union(pointer, target_type, value_type, value)
      end
    end

    def assign_to_union(union_pointer, union_type, type, value)
      if union_type.nilable?
        if value.type.kind == :integer
          value = @builder.int2ptr value, union_type.nilable_type.llvm_type
        end
        @builder.store value, union_pointer
        return
      end

      type_id_ptr, value_ptr = union_type_id_and_value(union_pointer)

      if type.union?
        casted_value = @builder.bit_cast(value, LLVM::Pointer(union_type.llvm_type))
        @builder.store @builder.load(casted_value), union_pointer
      elsif type.nilable?
        index = @builder.select null_pointer?(value), int(@mod.nil.type_id), int(type.nilable_type.type_id)

        @builder.store index, type_id_ptr

        casted_value_ptr = @builder.bit_cast value_ptr, LLVM::Pointer(type.nilable_type.llvm_type)
        @builder.store value, casted_value_ptr
      else
        index = type.type_id
        @builder.store int(index), type_id_ptr

        casted_value_ptr = @builder.bit_cast value_ptr, LLVM::Pointer(type.llvm_type)
        @builder.store value, casted_value_ptr
      end
    end

    def union_type_id_and_value(union_pointer)
      type_id_ptr = union_type_id(union_pointer)
      value_ptr = union_value(union_pointer)
      [type_id_ptr, value_ptr]
    end

    def union_type_id(union_pointer)
      gep union_pointer, 0, 0
    end

    def union_value(union_pointer)
      gep union_pointer, 0, 1
    end

    def gep(ptr, *indices)
      @builder.gep ptr, indices.map { |i| int(i) }
    end

    def null_pointer?(value)
      @builder.icmp :eq, @builder.ptr2int(value, LLVM::Int), int(0)
    end

    def not_null_pointer?(value)
      @builder.icmp :ne, @builder.ptr2int(value, LLVM::Int), int(0)
    end

    def malloc(type)
      @builder.malloc(type)
    end

    def memset(pointer, value, size)
      pointer = @builder.bit_cast pointer, LLVM::Pointer(LLVM::Int8)
      @builder.call @mod.memset(@llvm_mod), pointer, value, @builder.trunc(size, LLVM::Int32), int(4), int1(0)
    end

    def realloc(buffer, size)
      @builder.call @mod.realloc(@llvm_mod), buffer, size
    end

    def llvm_puts(string)
      @builder.call @mod.llvm_puts(@llvm_mod), @builder.global_string_pointer(string)
    end

    def alloca(type, name = '')
      in_alloca_block { @builder.alloca type, name }
    end

    def in_alloca_block
      old_block = @builder.insert_block
      @builder.position_at_end @alloca_block
      value = yield
      @builder.position_at_end old_block
      value
    end

    def llvm_self
      @vars['self'][:ptr]
    end

    def llvm_self_ptr
      if @type.hierarchy?
        ptr = @builder.load(union_value(llvm_self))
        self_ptr = @builder.bit_cast ptr, @type.base_type.llvm_type
      else
        self_ptr = llvm_self
      end
    end

    def llvm_nil
      int1(0)
    end

    def new_entry_block
      @alloca_block, @entry_block = new_entry_block_chain "alloca", "entry"
    end

    def new_entry_block_chain *names
      blocks = new_blocks *names
      @builder.position_at_end blocks.last
      blocks
    end

    def br_from_alloca_to_entry
      br_block_chain @alloca_block, @entry_block
    end

    def br_block_chain *blocks
      old_block = @builder.insert_block

      0.upto(blocks.count - 2) do |i|
        @builder.position_at_end blocks[i]
        @builder.br blocks[i + 1]
      end

      @builder.position_at_end old_block
    end

    def new_block(name)
      @fun.basic_blocks.append(name)
    end

    def new_blocks(*names)
      names.map { |name| new_block name }
    end
  end
end