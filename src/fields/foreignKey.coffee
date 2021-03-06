'use strict'

_               = require 'underscore'
knexConf        = require process.cwd() + '/knexfile'
knex            = require('knex')(knexConf[process.env.NODE_ENV])
fs              = require 'fs'
Joi             = require 'joi'

BaseField       = require './baseField'
BaseModel       = require './../model/baseModel'

foreignKeyAcceptedParameters = [
  'foreignKey'
  'referenceModel'
  'referenceField'
]

foreignKeyValidationMethods =
  foreignKey: 'validateForeignKey'


class ForeignKey extends BaseField

  # ForeignKey constructor
  # extends BaseField parameters with it's own parameters
  # as well as validation methods
  constructor: (attributes...) ->
    # extend BaseField accepted parameters with ForeignKey accepted parameters
    @constructor.acceptedParameters = _.union BaseField.acceptedParameters, foreignKeyAcceptedParameters
    # extend BaseField validation methods with ForeignKey validation methods
    @constructor.validationMethods = _.extend BaseField.validationMethods, foreignKeyValidationMethods

    referenceModel = attributes[0].referenceModel

    # specify 'foreignKey' attribute of the field as true
    _.extend attributes[0], { 'foreignKey': true }

    # if the 'referenceField' of FK is not set, then primaryKey of referencedModel
    # is taken as the 'referenceField'
    if not(_.has attributes[0], 'referenceField')
      _.extend attributes[0], { 'referenceField': referenceModel.metadata.primaryKey }

    # if the 'name' attribute of FK is not set, then camelCase name of referencedModel
    # is taken as the 'name' attribute e.g. AccountCategory -> accountCategory
    if not(_.has attributes[0], 'name')
      _.extend attributes[0], { 'name': referenceModel.metadata.model.substring(0, 1).toLowerCase() + referenceModel.metadata.model.substring(1) }

    # here we retrieve the 'dbField' attribute
    # it translates 'name' attribute to snake_case and appends '_id' to the field 'name'
    # e.g. accountCategory -> account_category_id
    if not(_.has attributes[0], 'dbField')
      _.extend attributes[0], { 'dbField': @getDbField(attributes[0].name) }

    # Joi validation schema for the foreign key is taken from related Model's reference field
    referenceFieldSchema = referenceModel::attributes[attributes[0].referenceField].attributes.schema
    if not(_.has attributes[0], 'schema')
      _.extend attributes[0], { schema: referenceFieldSchema }

    super

  # Instance method which validates if passed foreignKey value exists
  # in specified 'referenceModel' on specified 'referenceField'
  # @param [Any] value value for current foreign key field
  # @param [Object] trx transaction object in case when multiple records will be impacted
  validateForeignKey: (value, { trx } = {}) =>
    if value?
      sqlQuery = "SELECT EXISTS(SELECT 1 FROM #{@attributes.referenceModel.metadata.tableName}
                  WHERE #{@attributes.referenceField} = ?
                  AND is_deleted = false)"
      finalQuery = knex.raw(sqlQuery, [value])

      if trx?
        finalQuery.transacting(trx)

      return finalQuery.then (result) =>
        if result.rows[0].exists is false
          @attributes.errorMessages['foreignKey'] || "Specified #{@attributes.name} does not exist!"
      .catch (error) ->
        throw error
    return

  getDbField: (val) =>
    if not _.has @attributes, 'dbField'
      # we need to add the '_id' part, because we cannot pass attributes parameter
      # to '_camelToSnakeCase' method which defines if it is a foreign key
      # in this case we know it is a foreign key, so we can append the '_id'
      # part immediately
      return @constructor._camelToSnakeCase(val) + '_id'
    return @attributes.dbField


module.exports = ForeignKey
