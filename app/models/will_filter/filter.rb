#--
# Copyright (c) 2010-2011 Michael Berkovich
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

module WillFilter
  class Filter < ActiveRecord::Base
    set_table_name  :will_filter_filters
    serialize       :data
    before_save     :prepare_save
    after_find      :process_find
    
    #############################################################################
    # Basics 
    #############################################################################
    def initialize(model_class)
      super()
      self.model_class_name = model_class.to_s
    end
    
    def dup
      super.tap {|ii| ii.conditions = self.conditions.dup}
    end
    
    def prepare_save
      self.data = serialize_to_params
      self.type = self.class.name
    end
    
    def process_find
      @errors = {}
      deserialize_from_params(self.data)
    end
    
    #############################################################################
    # Defaults 
    #############################################################################
    def show_export_options?
      WillFilter::Config.exporting_enabled?
    end
  
    def show_save_options?
      WillFilter::Config.saving_enabled?
    end
  
    def match 
      @match ||= :all
    end
  
    def key 
      @key ||= ''
    end
  
    def errors 
      @errors ||= {}
    end
    
    def format
      @format ||= :html
    end
  
    def fields
      @fields ||= []
    end
    
    #############################################################################
    # a list of indexed fields where at least one of them has to be in a query
    # otherwise the filter may hang the database
    #############################################################################
    def required_condition_keys
      []
    end
    
    def model_class
      return nil unless model_class_name
      @model_class ||= model_class_name.constantize
    end
    
    def table_name
      model_class.table_name
    end
    
    def key=(new_key)
      @key = new_key
    end
    
    def match=(new_match)
      @match = new_match
    end
    
    #############################################################################
    # Inner Joins come in a form of 
    # [[joining_model_name, column_name], [joining_model_name, column_name]]
    #############################################################################
    def inner_joins
      []
    end
    
    def model_columns
      model_class.columns
    end
  
    def model_column_keys
      model_columns.collect{|col| col.name.to_sym}
    end
    
    def contains_column?(key)
      model_column_keys.index(key) != nil
    end
    
    def definition
      @definition ||= begin
        defs = {}
        model_columns.each do |col|
          #only show the following columns in the filter if the class matches "Person"
          if self.model_class_name=="Person"
            if ["recent_kscore","twitter_description","followers_count","twitter_location","name","twitter_handle","friends_count","facebook_url","linkedin_url","googleplus_url","li_interests","li_num_connections","li_headline","li_positions","li_industry","li_date_of_birth","li_specialties","li_honors","li_skills","li_educations","gender","statuses_count"].include? col.name

            defs[col.name.to_sym] = default_condition_definition_for(col.name, col.sql_type)
            end
          else
          defs[col.name.to_sym] = default_condition_definition_for(col.name, col.sql_type)
          end
        end
        inner_joins.each do |inner_join|
          join_class = association_class(inner_join)
          join_class.columns.each do |col|
            defs[:"#{join_class.to_s.underscore}.#{col.name.to_sym}"] = default_condition_definition_for(col.name, col.sql_type)
          end
        end
        
        defs
      end
    end
  
    def container_by_sql_type(type)
      raise WillFilter::FilterException.new("Unsupported data type #{type}") unless WillFilter::Config.data_types[type]
      WillFilter::Config.data_types[type]
    end
    
    def default_condition_definition_for(name, sql_data_type)
      type = sql_data_type.split(" ").first.split("(").first.downcase
      containers = container_by_sql_type(type)
      operators = {}
      containers.each do |c|
        raise WillFilter::FilterException.new("Unsupported container implementation for #{c}") unless WillFilter::Config.containers[c]
        container_klass = WillFilter::Config.containers[c].constantize
        container_klass.operators.each do |o|
          operators[o] = c
        end
      end
      
      if name == "id"
        operators[:is_filtered_by] = :filter_list 
      elsif "_id" == name[-3..-1]
        begin
          name[0..-4].camelcase.constantize
          operators[:is_filtered_by] = :filter_list 
        rescue  
        end
      end
      
      operators
    end
    
    def sorted_operators(opers)
      (WillFilter::Config.operator_order & opers.keys.collect{|o| o.to_s})
    end
    
    def first_sorted_operator(opers)
      sorted_operators(opers).first.to_sym
    end
  
    def default_order
      'id'
    end
    
    def order
      @order ||= default_order
    end
    
    def default_order_type
      'desc'
    end
  
    def order_type
      @order_type ||= default_order_type
    end
  
    def order_clause
      "#{order} #{order_type}"
    end
  
    def column_sorted?(key)
      key.to_s == order
    end
  
    def default_per_page
      100 
    end
    
    def per_page
      @per_page ||= default_per_page
    end
  
    def page
      @page ||= 1
    end
    
    def default_per_page_options
      [30, 40, 50, 100, 200, 300]
    end
    
    def per_page_options
      @per_page_options ||= default_per_page_options.collect{ |n| [n.to_s, n.to_s] }
    end
    
    def match_options
      [["all", "all"], ["any", "any"]]
    end
    
    def order_type_options
      [["desc", "desc"], ["asc", "asc"]]
    end
  
    #############################################################################
    # Can be overloaded for custom titles
    #############################################################################
    def condition_title_for(key)
        if key == :name
          title = 'Name'
        elsif key == :twitter_location
          title = 'Location'
        elsif key == :gender
          title = 'Gender'
        elsif key == :li_date_of_birth
          title = 'Birthday'          
        elsif key == :twitter_handle
          title = 'Twitter Username'
        elsif key == :twitter_description
          title = 'Twitter Bio'          
        elsif key == :followers_count
          title = 'Number of Followers'
        elsif key = :statuses_count
          title = 'Number of Tweets'          
        elsif key == :recent_kscore
          title = 'Klout Score'
        elsif key == :facebook_url
          title = 'Facebook URL'          
        elsif key == :linkedin_url
          title = 'LinkedIn URL'          
        elsif key == :li_headline
          title = 'LinkedIn Headline'
        elsif key == :li_industry
          title = 'Industry'          
        elsif key == :li_num_connections
          title = 'Number of LinkedIn Connections'          
        elsif key == :li_educations
          title = 'Education'          
        elsif key == :li_interests
          title = 'Interests'
        elsif key == :li_positions
          title = 'Job Positions'
        elsif key == :li_specialties
          title = 'Specialties'
        elsif key == :li_honors
          title = 'Honors'
        elsif key == :li_skills
          title = 'Skills'
        elsif key == :googleplus_url
          title = 'Google Plus URL'
        end
    end
    
    def condition_options
      @condition_options ||= begin
        opts = []
        definition.keys.each do |cond|
          opts << [condition_title_for(cond), cond.to_s]
        end
        opts.sort_by{ |i| i[0] }
      end
    end
    
    def operator_options_for(condition_key)
      condition_key = condition_key.to_sym if condition_key.is_a?(String)
      
      opers = definition[condition_key]
      raise WillFilter::FilterException.new("Invalid condition #{condition_key} for filter #{self.class.name}") unless opers
      sorted_operators(opers).collect{|o| [o.to_s.gsub('_', ' '), o]}
    end
    
    # called by the list container, should be overloaded in a subclass
    def value_options_for(condition_key)
      []
    end
    
    def container_for(condition_key, operator_key)
      condition_key = condition_key.to_sym if condition_key.is_a?(String)
  
      opers = definition[condition_key]
      raise WillFilter::FilterException.new("Invalid condition #{condition_key} for filter #{self.class.name}") unless opers
      oper = opers[operator_key]
      
      # if invalid operator_key was passed, use first operator
      oper = opers[first_sorted_operator(opers)] unless oper
      oper
    end
    
    def add_condition(condition_key, operator_key, values = [])
      add_condition_at(size, condition_key, operator_key, values)
    end
    
    def valid_operator?(condition_key, operator_key)
      condition_key = condition_key.to_sym if condition_key.is_a?(String)
      opers = definition[condition_key]
      return false unless opers
      opers[operator_key]!=nil
    end
    
    def add_condition_at(index, condition_key, operator_key, values = [])
      values = [values] unless values.instance_of?(Array)
      values = values.collect{|v| v.to_s}
  
      condition_key = condition_key.to_sym if condition_key.is_a?(String)
      
      unless valid_operator?(condition_key, operator_key)
        opers = definition[condition_key]
        operator_key = first_sorted_operator(opers)
      end
      
      condition = WillFilter::FilterCondition.new(self, condition_key, operator_key, container_for(condition_key, operator_key), values)
      @conditions.insert(index, condition)
    end
    
    #############################################################################
    # options always go in [NAME, KEY] format
    #############################################################################
    def default_condition_key
      condition_options.first.last
    end
    
    #############################################################################
    # options always go in [NAME, KEY] format
    #############################################################################
    def default_operator_key(condition_key)
      operator_options_for(condition_key).first.last
    end
    
    def conditions=(new_conditions) 
      @conditions = new_conditions
    end
    
    def conditions
      @conditions ||= []
    end
    
    def condition_at(index)
      conditions[index]
    end
    
    def condition_by_key(key)
      conditions.each do |c|
        return c if c.key==key
      end
      nil
    end
    
    def size
      conditions.size
    end
    
    def add_default_condition_at(index)
      add_condition_at(index, default_condition_key, default_operator_key(default_condition_key))
    end
    
    def remove_condition_at(index)
      conditions.delete_at(index)
    end
    
    def remove_all
      @conditions = []
    end
  
    #############################################################################
    # Serialization 
    #############################################################################
    def serialize_to_params(merge_params = {})
      params = {}
      params[:wf_type]          = self.class.name
      params[:wf_match]         = match
      params[:wf_model]         = model_class_name
      params[:wf_order]         = order
      params[:wf_order_type]    = order_type
      params[:wf_per_page]      = per_page
      params[:wf_export_fields] = fields.join(',')
      params[:wf_export_format] = format
      
      0.upto(size - 1) do |index|
        condition = condition_at(index)
        condition.serialize_to_params(params, index)
      end
      
      params.merge(merge_params)
    end
    
    #############################################################################
    # allows to create a filter from params only
    #############################################################################
    def self.deserialize_from_params(params)
      params = HashWithIndifferentAccess.new(params) unless params.is_a?(HashWithIndifferentAccess)
      params[:wf_type] = self.name unless params[:wf_type]
      params[:wf_type].constantize.new(params[:wf_model]).deserialize_from_params(params)
    end
    
    def deserialize_from_params(params)
      params = HashWithIndifferentAccess.new(params) unless params.is_a?(HashWithIndifferentAccess)
      @conditions = []
      @match                = params[:wf_match]       || :all
      @key                  = params[:wf_key]         || self.id.to_s
      self.model_class_name = params[:wf_model]       if params[:wf_model]
      
      @per_page             = params[:wf_per_page]    || default_per_page
      @page                 = params[:page]           || 1
      @order_type           = params[:wf_order_type]  || default_order_type
      @order                = params[:wf_order]       || default_order
      
      self.id   =  params[:wf_id].to_i  unless params[:wf_id].blank?
      self.name =  params[:wf_name]     unless params[:wf_name].blank?
      
      @fields = []
      unless params[:wf_export_fields].blank?
        params[:wf_export_fields].split(",").each do |fld|
          @fields << fld.to_sym
        end
      end
  
      if params[:wf_export_format].blank?
        @format = :html
      else  
        @format = params[:wf_export_format].to_sym
      end
      
      i = 0
      while params["wf_c#{i}"] do
        conditon_key = params["wf_c#{i}"]
        operator_key = params["wf_o#{i}"]
        values = []
        j = 0
        while params["wf_v#{i}_#{j}"] do
          values << params["wf_v#{i}_#{j}"]
          j += 1
        end
        i += 1
        add_condition(conditon_key, operator_key.to_sym, values)
      end
  
      if params[:wf_submitted] == 'true'
        validate!
      end
  
      return self
    end
    
    #############################################################################
    # Validations 
    #############################################################################
    def errors?
     (@errors and @errors.size > 0)
    end
    
    def empty?
      size == 0
    end
  
    def has_condition?(key)
      condition_by_key(key) != nil
    end
  
    def valid_format?
      WillFilter::Config.default_export_formats.include?(format.to_s)
    end
  
    def required_conditions_met?
      return true if required_condition_keys.blank?
      sconditions = conditions.collect{|c| c.key.to_s}
      rconditions = required_condition_keys.collect{|c| c.to_s}
      not (sconditions & rconditions).empty?
    end
    
    def validate!
      @errors = {}
      0.upto(size - 1) do |index|
        condition = condition_at(index)
        err = condition.validate
        @errors[index] = err if err
      end
      
      unless required_conditions_met?
        @errors[:filter] = "Filter must contain at least one of the following conditions: #{required_condition_keys.join(", ")}"
      end
      
      errors?
    end
    
    #############################################################################
    # SQL Conditions 
    #############################################################################
    def sql_conditions
      @sql_conditions  ||= begin
  
        if errors? 
          all_sql_conditions = [" 1 = 2 "] 
        else
          all_sql_conditions = [""]
          0.upto(size - 1) do |index|
            condition = condition_at(index)
            sql_condition = condition.container.sql_condition
            
            unless sql_condition
              raise WillFilter::FilterException.new("Unsupported operator #{condition.operator_key} for container #{condition.container.class.name}")
            end
            
            if all_sql_conditions[0].size > 0
              all_sql_conditions[0] << ( match.to_sym == :all ? " AND " : " OR ")
            end
            
            all_sql_conditions[0] << sql_condition[0]
            sql_condition[1..-1].each do |c|
              all_sql_conditions << c
            end
          end
        end
        
        all_sql_conditions
      end
    end
    
    def debug_conditions(conds)
      all_conditions = []
      conds.each_with_index do |c, i|
        cond = ""
        if i == 0
          cond << "\"<b>#{c}</b>\""
        else  
          cond << "<br>&nbsp;&nbsp;&nbsp;<b>#{i})</b>&nbsp;"
          if c.is_a?(Array)
            cond << "["
            cond << (c.collect{|v| "\"#{v.strip}\""}.join(", "))
            cond << "]"
          elsif c.is_a?(Date)  
            cond << "\"#{c.strftime("%Y-%m-%d")}\""
          elsif c.is_a?(Time)  
            cond << "\"#{c.strftime("%Y-%m-%d %H:%M:%S")}\""
          elsif c.is_a?(Integer)  
            cond << c.to_s
          else  
            cond << "\"#{c}\""
          end
        end
        
        all_conditions << cond
      end
      all_conditions.join("")
    end
  
    def debug_sql_conditions
      debug_conditions(sql_conditions)
    end
  
    #############################################################################
    # Saved Filters 
    #############################################################################
    def saved_filters(include_default = true)
      @saved_filters ||= begin
        filters = []
      
        if include_default
          filters = default_filters
          if (filters.size > 0)
            filters.insert(0, ["-- Select Default Filter --", "-1"])
          end
        end
  
        if include_default
          conditions = ["type = ? and model_class_name = ?", self.class.name, self.model_class_name]
        else
          conditions = ["model_class_name = ?", self.model_class_name]
        end
  
        if WillFilter::Config.user_filters_enabled?
          conditions[0] << " and user_id = ? "
          if WillFilter::Config.current_user and WillFilter::Config.current_user.id
            conditions << WillFilter::Config.current_user.id
          else
            conditions << "0"
          end
        end
  
        user_filters = WillFilter::Filter.find(:all, :conditions => conditions)
        
        if user_filters.size > 0
          filters << ["-- Select Saved Filter --", "-2"] if include_default
          
          user_filters.each do |filter|
            filters << [filter.name, filter.id.to_s]
          end
        end
          
        filters
      end
    end
    
    #############################################################################
    # overload this method if you don't want to allow empty filters
    #############################################################################
    def default_filter_if_empty
      nil
    end
      
    def handle_empty_filter!
      return unless empty?
      return if default_filter_if_empty.nil?
      load_filter!(default_filter_if_empty)
    end
    
    def default_filters
      []
    end
  
    def default_filter_conditions(key)
      []
    end
    
    def load_default_filter(key)
      default_conditions = default_filter_conditions(key)
      return if default_conditions.nil? or default_conditions.empty?
      
      unless default_conditions.first.is_a?(Array)
        add_condition(*default_conditions)
        return
      end
      
      default_conditions.each do |default_condition|
        add_condition(*default_condition)
      end
    end
    
    def reset!
      remove_all
      @sql_conditions = nil
      @results = nil
    end
    
    def load_filter!(key_or_id)
      reset!
      @key = key_or_id.to_s
      
      load_default_filter(key)
      return self unless empty?
      
      filter = WillFilter::Filter.find_by_id(key_or_id.to_i)
      raise WillFilter::FilterException.new("Invalid filter key #{key_or_id.to_s}") if filter.nil?
      filter
    end
  
    #############################################################################
    # Export Filter Data
    #############################################################################
    def export_formats
      formats = []
      formats << ["-- Generic Formats --", -1]
      WillFilter::Config.default_export_formats.each do |frmt|
        formats << [frmt, frmt]
      end
      if custom_formats.size > 0
        formats << ["-- Custom Formats --", -2]
        custom_formats.each do |frmt|
          formats << frmt
        end
      end
      formats
    end
  
    def custom_format?
      custom_formats.each do |frmt|
        return true if frmt[1].to_sym == format
      end
      false
    end
    
    def custom_formats
      []
    end
    
    def process_custom_format
      ""
    end

    def association_name(inner_join)
      (inner_join.is_a?(Array) ? inner_join.first : inner_join).to_sym
    end
    
    def association_class(inner_join)
      model_class.new.association(association_name(inner_join)).build.class
    end  
      
    # deprecated for Rails 3.0 and up
    def joins
      return nil if inner_joins.empty?
      inner_joins.collect do |inner_join|
        join_table_name = association_class(inner_join).table_name
        join_on_field = inner_join.last.to_s
        "INNER JOIN #{join_table_name} ON #{join_table_name}.id = #{table_name}.#{join_on_field}"
      end
    end
    
    def results
      @results ||= begin
        handle_empty_filter! 
        recs = model_class.where(sql_conditions).order(order_clause)
        inner_joins.each do |inner_join|
          recs = recs.joins(association_name(inner_join))
        end
        recs = recs.page(page).per(per_page)
        recs.wf_filter = self
        recs
      end
    end
    
    # sums up the column for the given conditions
    def sum(column_name)
      model_class.sum(column_name, :conditions => sql_conditions)
    end
  end
end
