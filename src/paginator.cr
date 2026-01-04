class Carafe::Paginator
  include Crinja::Object::Auto

  getter items : Array(Resource)

  getter index : Int32

  getter pages : Array(Resource)

  property! next : Resource

  property! previous : Resource

  property! first : Resource

  property! last : Resource

  # Jekyll compatibility methods
  def page : Int32
    @index + 1
  end

  def per_page : Int32
    @items.size
  end

  def total_pages : Int32
    @pages.size
  end

  def total_items : Int32
    # Sum of all items across all pages
    # @pages is an array of Resources, not Paginators
    # We need to get the items from each page's paginator
    @pages.sum do |page|
      if paginator = page.paginator
        paginator.items.size
      else
        0
      end
    end
  end

  def previous_page : Int32?
    @index > 0 ? @index : nil
  end

  def previous_page_path : String
    if prev = @previous
      prev.url.try(&.to_s) || ""
    else
      ""
    end
  end

  def next_page : Int32?
    @index < @pages.size - 1 ? @index + 2 : nil
  end

  def next_page_path : String
    if nxt = @next
      nxt.url.try(&.to_s) || ""
    else
      ""
    end
  end

  def initialize(@items : Array(Resource), @index : Int, @pages : Array(Resource))
  end
end
