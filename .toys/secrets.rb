# frozen_string_literal: true

desc "Edit rails credentials"

include :exec, exit_on_nonzero_status: true

def run
  exec("EDITOR=\"${EDITOR} --wait\"  bin/rails credentials:edit")
end
