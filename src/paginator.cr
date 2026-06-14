class Carafe::Paginator
  getter items : Array(Resource)
  getter index : Int32
  getter pages : Array(Resource)
  getter per_page_limit : Int32  # Store configured per-page limit

  property! next : Resource
  property! previous : Resource
  property! first : Resource
  property! last : Resource

  # Jekyll compatibility methods
  def page : Int32
    @index + 1
  end

  def per_page : Int32
    @per_page_limit
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

  def first_page : Int32
    1
  end

  def last_page : Int32
    total_pages
  end

  def first_page_path : String
    if first = @first
      first.url.try(&.to_s) || ""
    else
      ""
    end
  end

  def last_page_path : String
    if last = @last
      last.url.try(&.to_s) || ""
    else
      ""
    end
  end

  def page_trail : Array(PageTrail)
    trail = [] of PageTrail
    start = [1, page - 2].max
    finish = [total_pages, page + 2].min
    (start..finish).each do |num|
      page_resource = @pages[num - 1]?
      path = page_resource.try(&.url).try(&.to_s) || ""
      trail << PageTrail.new(num, path)
    end
    trail
  end

  class PageTrail
    getter num : Int32
    getter path : String

    def initialize(@num : Int32, @path : String)
    end
  end

  def initialize(@items : Array(Resource), @index : Int, @pages : Array(Resource), @per_page_limit : Int32? = nil)
    @per_page_limit ||= @items.size
  end
end
