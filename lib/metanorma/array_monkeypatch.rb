# TODO sidesteps bibdata redefinition of filter, will remove

module Metanorma
  module ArrayMonkeypatch
    class ::Array
      alias filter select
    end
  end
end
