module Metanorma
  class Collection
    METANORMA_LOG_MESSAGES = {
      # rubocop:disable Naming/VariableNumber
      "METANORMA_1": { category: "Cross-References",
                       error: "Missing cross-reference: %s",
                       severity: 2 },
      "METANORMA_2": { category: "Cross-References",
                       error: "[metanorma] Cannot find crossreference to document %s in document %s.",
                       severity: 2 },
      "METANORMA_3": { category: "Cross-References",
                       error: "<strong>** Unresolved reference to document %s from eref</strong>",
                       severity: 2 },
      "METANORMA_4": { category: "Rendering",
                       error: "Collection member %s: expected output " \
                              "file not generated: %s",
                       severity: 0 },
      "METANORMA_5": { category: "Rendering",
                       error: "Collection member %s: rendering error: %s",
                       severity: 0 },
    }.freeze
    # rubocop:enable Naming/VariableNumber
  end
end
