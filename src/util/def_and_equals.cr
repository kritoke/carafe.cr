module Util::DefAndEquals
  macro included
    macro finished
      ::Util::DefAndEquals.__generate_def_and_equals
    end
  end

  macro __generate_def_and_equals
    {% if @type.class? || @type.struct? %}
      def ==(other : self)
        {% for field in @type.instance_vars %}
          return false unless @{{field.id}} == other.@{{field.id}}
        {% end %}
        true
      end

      def hash(hasher)
        {% for field in @type.instance_vars %}
          hasher = @{{field.id}}.hash(hasher)
        {% end %}
        hasher
      end
    {% end %}
  end
end
