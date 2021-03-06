// Generated by CoffeeScript 1.10.0
(function() {
  'use strict';
  var ForeignKey, Promise, Serializer, _, moduleKeywords,
    indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; },
    slice = [].slice;

  _ = require('underscore');

  Promise = require('bluebird');

  ForeignKey = require('./../fields/foreignKey');

  moduleKeywords = ['extended', 'included'];

  Serializer = (function() {
    Serializer.applyConfiguration = function(obj) {
      var key, ref, value;
      this.prototype['config'] = {};
      for (key in obj) {
        value = obj[key];
        if (indexOf.call(moduleKeywords, key) < 0) {
          this.prototype['config'][key] = value;
        }
      }
      if ((ref = obj.included) != null) {
        ref.apply(this);
      }
      return this;
    };

    function Serializer() {
      var attributes, base, base1, base2;
      attributes = 1 <= arguments.length ? slice.call(arguments, 0) : [];
      this.attributes = attributes;
      _.each(this.attributes[0], (function(_this) {
        return function(val, key) {
          if (!(indexOf.call(_this.constructor.acceptedParameters, key) >= 0)) {
            throw new TypeError("Parameter '" + key + "' is not accepted in " + _this.constructor.name);
          }
        };
      })(this));
      if ((base = this.config).readOnlyFields == null) {
        base.readOnlyFields = [];
      }
      if ((base1 = this.config).fields == null) {
        base1.fields = [];
      }
      if ((base2 = this.config).excludeFields == null) {
        base2.excludeFields = [];
      }
      if ((this.attributes[0] != null) && (this.attributes[0].fields != null) && this.attributes[0].fields.length > 0) {
        this.config.fields = _.clone(this.attributes[0].fields);
      }
      if (this.config.fields.length === 0 && this.config.readOnlyFields.length === 0) {
        this.serializerFields = _.keys(this.config.model.prototype.attributes);
      } else {
        this.serializerFields = _.union(this.config.fields, this.config.readOnlyFields);
      }
      _.each(this.serializerFields, (function(_this) {
        return function(val, key) {
          if (typeof val === 'string' && (_this.config.model.prototype.attributes[val] == null)) {
            throw new Error("Key '" + val + "' does not match any attribute of model " + _this.config.model.metadata.model);
          }
        };
      })(this));
      this.serializerFieldsKeys = _.map(this.serializerFields, (function(_this) {
        return function(val, key) {
          var currentKey;
          currentKey = val.constructor.name === 'String' ? val : (_.keys(val))[0];
          if (indexOf.call(_this.config.excludeFields, currentKey) < 0) {
            return currentKey;
          }
        };
      })(this));
      this.serializerFieldsKeys = _.without(this.serializerFieldsKeys, void 0);
      if (this.serializerFieldsKeys.length === 0) {
        throw new Error(this.constructor.name + " does not have any field specified!");
      }
    }

    Serializer.prototype.getData = function() {
      return new Promise(function(resolve, reject) {
        return resolve(this.data);
      });
    };

    Serializer.prototype.setData = function(data) {
      return this.data = data;
    };

    return Serializer;

  })();

  module.exports = Serializer;

}).call(this);
