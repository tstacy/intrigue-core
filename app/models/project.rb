module Intrigue
  module Model
    class Project < Sequel::Model
      plugin :validation_helpers
        plugin :serialization, :json, :seeds, :options, :handlers, :additional_exception_list

      one_to_many :logger
      one_to_many :task_results
      one_to_many :scan_results

      include Intrigue::Model::Mixins::Handleable
      include Intrigue::Model::Mixins::MatchExceptions

      def validate
        super
        validates_unique(:name)
      end

      def delete!
        self.scan_results.each{|x| x.delete }
        self.task_results.each{|x| x.delete }
        self.entities.each{|x| x.delete }
        self.delete
      end

      def entities
        Intrigue::Model::Entity.scope_by_project(self.name)
      end

      def seed_entity?(entity_name, type_string)

        if seeds
          seeds.each do |s|
            return true if entity_name == s["name"] && (type_string == s["type"] || type_string == "Intrigue::Entity#{s["type"]}")
          end
        end

      false
      end

      def export_hash
        {
          :id => id,
          :name => "#{name}",
          :seeds => seeds,
          :entities => entities.map {|e| e.export_hash }
          #:task_results => task_results.map {|t| t.export_hash }
          #:scan_results => scan_results.map {|s| s.export_hash }
        }
      end

      def export_json
        export_hash.merge("generated_at" => "#{DateTime.now}").to_json
      end

      def export_csv

        output_string = ""
        self.entities.paged_each do |e|
          output_string << e.export_csv << "\n"
        end

      output_string
      end

      def export_csv_by_type(type_string)
        Intrigue::Model::Entity.scope_by_project_and_type(self.name, type_string).map { |e| e.export_csv }.join("\n")
      end

      def export_applications_csv
        out = ""
        out << "IpAddress,Uri,Title,Fingerprint,Javascript,XFrameOptions,Form,Dir Listing,Http Auth,Forms Auth,User Account,Any Auth\n"

        self.entities.sort_by{|e| e.to_s }.each do |x|

          next unless x.kind_of? Intrigue::Entity::Uri

          # Resolve the host
          host_id = x.get_detail("host_id")
          host = Intrigue::Model::Entity.scope_by_project(self).first(:id => host_id)
          if host
            out << "#{host.name},"
          else
            out << "[Unknown host],"
          end

          out << "#{x.name.gsub(",",";")},"

          #products = x.get_detail("products")
          #product_string = products.map{|p| p["matched"] }.compact.join("; ") if products
          #out << "#{product_string}" if product_string

          page_title = x.get_detail("title")
          page_title_string = page_title.gsub(",","") if page_title
          out << "#{page_title_string},"


          fingerprint = x.get_detail("fingerprint")
          if fingerprint
            fingerprint.each do |f|
              temp = "#{f["vendor"]}"
              temp << " #{f["product"]}"
              temp << " #{f["version"]}" if f["version"]
              temp << " #{f["update"]}"  if f["update"]
              temp << " | "
              out << temp.gsub(",",";")
            end
          end
          out << ","

          fingerprint = x.get_detail("javascript")
          if fingerprint
            fingerprint.each do |f|
              temp = "#{f["library"]}"
              temp << " #{f["version"]}"
              temp << " | "
              out << temp.gsub(",",";")
            end
          end
          out << ","

          # authentication
          configuration = x.get_detail("configuration")
          http_auth = false
          forms_auth = false
          any_auth = false
          x_frame_options = false
          if configuration
            configuration.each do |c|
              if c["name"] == "Authentication - Forms"
                forms_auth = c["result"]
              elsif c["name"] == "Authentication - HTTP"
                http_auth = c["result"]
              elsif c["name"] == "Authentication - User Account Required"
                user_account = c["result"]
              elsif c["name"] == "Content - Form Detected"
                form_detected = c["result"]
              elsif c["name"] == "Content - Directory Listing"
                dir_listing_detected = c["result"]
              elsif c["name"] == "Header Existence - X-Frame-Options"
                x_frame_options = true
              end
            end

            # Calculated
            any_auth = true if (forms_auth || http_auth)
          end

          out << "#{x_frame_options},#{form_detected},#{dir_listing_detected},#{http_auth},#{forms_auth},#{user_account},#{any_auth}\n"


        end

      out
      end

    end
  end
end
