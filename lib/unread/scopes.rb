module Unread
  module Readable
    module Scopes
      def join_read_marks(member)
        assert_reader(member)

        joins "LEFT JOIN #{ReadMark.table_name} as read_marks ON read_marks.readable_type  = '#{base_class.name}'
                                   AND read_marks.readable_id    = #{table_name}.#{primary_key}
                                   AND read_marks.member_id        = #{member.id}
                                   AND read_marks.timestamp     >= #{table_name}.#{readable_options[:on]}"
      end

      def unread_by(member)
        result = join_read_marks(member).
                 where('read_marks.id IS NULL')

        if global_time_stamp = member.read_mark_global(self).try(:timestamp)
          result = result.where("#{table_name}.#{readable_options[:on]} > '#{global_time_stamp.to_s(:db)}'")
        end

        result
      end

      def with_read_marks_for(member)
        join_read_marks(member).select("#{table_name}.*, read_marks.id AS read_mark_id")
      end
    end
  end
end
