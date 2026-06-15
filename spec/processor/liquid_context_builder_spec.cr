require "spec"
require "../../src/site"
require "../../src/processor/liquid"
require "../../src/processor/layout"

# Characterization specs for the canonical Liquid context shape.
#
# These specs assert the TARGET shape that `Carafe::LiquidContextBuilder` will
# provide once implemented (OpenSpec: unify-liquid-context-builder). Until the
# module exists (Phase 2), these are bare `pending` placeholders — they do not
# reference the not-yet-defined constant, so the suite compiles.
#
# The live RED signal in Phase 1 is carried by
# `liquid_context_parity_spec.cr`, which runs against the *current* processors
# and fails on the layout↔page-context divergence.
#
# Phase 2 turns each `pending` into an `it` block with the assertion body.

describe "Liquid context canonical shape" do
  pending "Carafe::LiquidContextBuilder exists and responds to build"
  pending "LiquidContextBuilder.build returns a Liquid::Context"

  pending "site.collections is a hash keyed by collection label"
  pending "site.posts is present and sorted newest-first"
  pending "site.posts is present (empty) when no posts collection exists"
  pending "site.config.source is exposed"
  pending "site.data is exposed"
  pending "scalar metadata (title/description/url) defaults to empty string"
  pending "doc.tags and doc.categories are always arrays"
  pending "LiquidContextBuilder.build does not write to STDERR"
end
