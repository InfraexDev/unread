module Unread
  module Readable
    module ClassMethods
      def mark_as_read!(target, options)
        raise ArgumentError unless options.is_a?(Hash)

        member = options[:for]
        assert_reader(member)

        if target == :all
          reset_read_marks_for_user(member)
        elsif target.is_a?(Array)
          mark_array_as_read(target, member)
        else
          raise ArgumentError
        end
      end

      def mark_array_as_read(array, member)
        ReadMark.transaction do
          array.each do |obj|
            raise ArgumentError unless obj.is_a?(self)

            rm = obj.read_marks.where(:member_id => member.id).first || obj.read_marks.build(:member_id => member.id)
            rm.timestamp = obj.send(readable_options[:on])
            rm.save!
          end
        end
      end

      # A scope with all items accessable for the given user
      # It's used in cleanup_read_marks! to support a filtered cleanup
      # Should be overriden if a user doesn't have access to all items
      # Default: User has access to all items and should read them all
      #
      # Example:
      #   def Message.read_scope(user)
      #     user.visible_messages
      #   end
      def read_scope(member)
        self
      end

      def cleanup_read_marks!
        assert_reader_class

        ReadMark.reader_class.find_each do |member|
          ReadMark.transaction do
            if oldest_timestamp = read_scope(member).unread_by(member).minimum(readable_options[:on])
              # There are unread items, so update the global read_mark for this user to the oldest
              # unread item and delete older read_marks
              update_read_marks_for_user(member, oldest_timestamp)
            else
              # There is no unread item, so deletes all markers and move global timestamp
              reset_read_marks_for_user(member)
            end
          end
        end
      end

      def update_read_marks_for_user(member, timestamp)
        # Delete markers OLDER than the given timestamp
        member.read_marks.where(:readable_type => self.base_class.name).single.older_than(timestamp).delete_all

        # Change the global timestamp for this user
        rm = member.read_mark_global(self) || member.read_marks.build(:readable_type => self.base_class.name)
        rm.timestamp = timestamp - 1.second
        rm.save!
      end

      def reset_read_marks_for_all
        ReadMark.transaction do
          ReadMark.delete_all :readable_type => self.base_class.name
          ReadMark.connection.execute <<-EOT
            INSERT INTO #{ReadMark.table_name} (member_id, readable_type, timestamp)
            SELECT #{ReadMark.reader_class.primary_key}, '#{self.base_class.name}', '#{Time.current.to_s(:db)}'
            FROM #{ReadMark.reader_class.table_name}
          EOT
        end
      end

      def reset_read_marks_for_user(member)
        assert_reader(member)

        ReadMark.transaction do
          ReadMark.delete_all :readable_type => self.base_class.name, :member_id => member.id
          ReadMark.create!    :readable_type => self.base_class.name, :member_id=> member.id, :timestamp => Time.current
        end
      end

      def assert_reader(member)
        assert_reader_class

        raise ArgumentError, "Class #{member.class.name} is not registered by acts_as_reader!" unless member.is_a?(ReadMark.reader_class)
        raise ArgumentError, "The given member has no id!" unless member.id
      end

      def assert_reader_class
        raise RuntimeError, 'There is no class using acts_as_reader!' unless ReadMark.reader_class
      end
    end

    module InstanceMethods
      def unread?(member)
        if self.respond_to?(:read_mark_id)
          # For use with scope "with_read_marks_for"
          return false if self.read_mark_id

          if global_timestamp = member.read_mark_global(self.class).try(:timestamp)
            self.send(readable_options[:on]) > global_timestamp
          else
            true
          end
        else
          !!self.class.unread_by(member).exists?(self) # Rails4 does not return true/false, but nil/count instead.
        end
      end

      def mark_as_read!(options)
        member = options[:for]
        self.class.assert_reader(member)

        ReadMark.transaction do
          if unread?(member)
            rm = read_mark(member) || read_marks.build(:member_id => member.id)
            rm.timestamp = self.send(readable_options[:on])
            rm.save!
          end
        end
      end

      def read_mark(member)
        read_marks.where(:member_id => member.id).first
      end
    end
  end
end
