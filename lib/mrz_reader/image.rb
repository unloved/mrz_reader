require "mini_magick"
require 'pry'
require 'rtesseract'

module MrzReader
  class Image
    attr_reader :path, :debug

    def self.parse path, debug=false
      self.new(path, debug).parse
    end

    def initialize path, debug=false
      @path = path
      @debug = debug
    end

    def parse
      @image = MiniMagick::Image.open(path)
      @image.auto_orient

      @temp_image = MiniMagick::Image.open(path)
      @temp_image.auto_orient
      find_roi

      if !@roi
        @image.rotate("90")
        @temp_image = MiniMagick::Image.open(@image.path)
        find_roi
      end

      if @roi
        mrz = crop_image_for_mrz
        text = recognize(mrz)
      end
      text
    end

    def find_roi
      # @temp_image.format('png')
      if debug
        prepare_temp_image(@temp_image)
      else
        @temp_image.combine_options do |b|
          prepare_temp_image(b)
        end
      end
      compute_roi(@temp_image)
    end

    def prepare_temp_image(image)
      resize_image(image)
      make_grey(image)
      blur_image(image)
      use_blackhat_filter(image)
      use_sobel_edge_filter(image)
      use_close_filter(image)
      normalize_image(image)
      use_close_filter2(image)
      # use_close_filter3(image)
      # make_erode(image)
      # image.colorspace('Gray')
      # image.colors(2)
      image.monochrome
    end

    private

    def rect_kernel
      @rect_kernel ||= get_rect_kernel(9, 5)
    end

    def resize_image image
      image.resize(500)
      image.write("./tmp/step1.png") if debug
    end

    def make_grey image
      image.colorspace('Gray')
      image.write "./tmp/step2.png" if debug
    end

    def blur_image image
      image.blur("5x5: #{get_rect_kernel(5, 5).map{|x| x.join(',')}.join(' ')}")
      image.write "./tmp/step3.png" if debug
    end

    def use_blackhat_filter image
      image.depth(32)
      image.morphology('BottomHat', "9x5: #{rect_kernel.map{|x| x.join(',')}.join(' ')}")
      image.write "./tmp/step4.png" if debug
    end

    def use_sobel_edge_filter image
      if debug
        image.combine_options do |b|
          b.depth(32)
          # @image.morphology('Convolve', "3x3: 3,0,-3 10,0,-10 3,0,-3")
          b.morphology('Convolve', 'Sobel')
        end

        image.write "./tmp/step5.png"
      else
        image.depth(32)
        image.morphology('Convolve', 'Sobel')
      end
    end

    def normalize_image image
      image.monochrome
      # image.colors('2')
      # image.normalize
      image.write "./tmp/step7.png" if debug
    end

    def use_close_filter image
      image.morphology('Close', "9x5: #{rect_kernel.map{|x| x.join(',')}.join(' ')}")
      image.write "./tmp/step6.png" if debug
    end

    def use_close_filter2 image
      # image.morphology('Close', "19x19: #{get_rect_kernel(19, 19).map{|x| x.join(',')}.join(' ')}")
      image.morphology('Close', "9x5: #{rect_kernel.map{|x| x.join(',')}.join(' ')}")
      image.write "./tmp/step8.png" if debug
    end

    def use_close_filter3 image
      image.morphology('Close', "19x19: #{get_rect_kernel(19, 19).map{|x| x.join(',')}.join(' ')}")
      # image.morphology('Close', "9x5: #{rect_kernel.map{|x| x.join(',')}.join(' ')}")
      image.write "./tmp/step9.png" if debug
    end

    def make_erode image
      # 4.times do
      4.times do
        image.morphology('Erode', "3x3: #{get_rect_kernel(3, 3).map{|x| x.join(',')}.join(' ')}")
      end

      8.times do
        image.morphology('Dilate', "3x3: #{get_rect_kernel(3, 3).map{|x| x.join(',')}.join(' ')}")
      end
      image.colors('2')
      image.normalize

      image.write "./tmp/step10.png" if debug
    end

    def compute_roi image
      manager = MrzReader::RoiManager.new(image, debug)
      @roi = manager.compute
    end

    def crop_image_for_mrz
      image_ratio = @image.width / @temp_image.width.to_f
      @image.crop("#{@roi.crop_width*image_ratio}x#{@roi.crop_height*image_ratio}+#{@roi.crop_x1*image_ratio}+#{@roi.crop_y1*image_ratio}")
      @image.colorspace('Gray')
      # @image.colors(2)
      # @image.monochrome
      # @image.morphology('Close', "3x3: #{get_rect_kernel(3,3).map{|x| x.join(',')}.join(' ')}")
      # @image.threshold('0%')
      @image.write "./tmp/mrz.png" if debug
      @image
    end

    def get_rect_kernel w, h
      Array.new(w) {Array.new(h, 1)}
    end

    def recognize mrz_image
      tesseract = ::RTesseract.new(
        mrz_image.path,
        lang: 'mrz',
        tessedit_char_whitelist: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<",
        tessdata_dir: File.expand_path(File.join(File.dirname(__FILE__), '../../vendor'))
      )
      tesseract.to_s.lines.map(&:strip).find_all{|l| !l.empty?}
    end
  end
end