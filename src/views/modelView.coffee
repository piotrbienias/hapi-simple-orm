'use strict'

_           = require 'underscore'
Joi         = require 'joi'
Boom        = require 'boom'

BaseView    = require './baseView'

moduleKeywords = ['extended', 'included']

require 'datejs'


class ModelView extends BaseView

  @applyConfiguration: (obj) ->
    @::['config'] = {}
    for key, value of obj when key not in moduleKeywords
      @::['config'][key] = value

    obj.included?.apply(@)
    this

  # every 'ModelView' instance must obtain two params
  # @param [Object] server current server's instance
  # @param [Object] options options of current routing module
  constructor: (@server, @defaultOptions) ->
    # check if Model was specified in configuration attribute of the ModelView
    if @config? and not @config.model?
      throw new Error 'You must specify \'config.model\' class attribute of ModelView!'

    # server and options are required parameters
    if not @server?
      throw new Error 'You need to pass \'server\' instance to ModelView constructor!'

    # set default errorMessages attribute of configuration to empty object {}
    @config.errorMessages ?= {}
    # if the pluralName of Model was not specified, we simply append 's' to Model's name
    @config.pluralName ?= "#{@config.model.metadata.model}s"

    # if serializer was not specified in the configuration, set it to undefined
    @config.serializer ?= undefined

    super

  # extend defaultOptions with extraOptions
  # works recursively
  # @params [Object] defaultOptions defaultOptions of this ModelView
  # @params [Object] extraOptions additional options passed to route method
  __extendProperties: (defaultOptions, extraOptions) ->
    _.each extraOptions, (val, key) =>
      if val? and val.constructor? and val.constructor.name is 'Object' and not (_.isEmpty val)
        defaultOptions[key] = defaultOptions[key] or {}
        @__extendProperties defaultOptions[key], val
      else
        defaultOptions[key] = val
    defaultOptions

  # method which is used to extend (or overwrite) current routing object
  # @param [Object] routeObject current route object and it's attributes
  # @param [Object] options options that will be used to extend/overwrite existing routeObject
  _extendRouteObject: (routeObject, options) ->
    if options? and _.isObject(options)
      # separately assign method and path attributes of the route, if they were passed
      routeObject.method = options.method or routeObject.method
      routeObject.path = options.path or routeObject.path

    # if 'options.config' passed to routing method is undefined, set it to empty object
    options.config ?= {}

    if (rejectedOptions = _.difference _.keys(options.config), @constructor.getAcceptableRouteOptions()).length > 0
      throw new Error "Options #{rejectedOptions} are not accepted in route object!"

    # here we extend current route object with combination of 'defaultOptions' and 'options'
    # passed directly to the current routing method
    # result is full route configuration object
    # but first we need to create copy of 'defaultOptions' in order to omit reference problems
    defaultOptionsCopy = @__extendProperties {}, @defaultOptions
    @__extendProperties routeObject.config, (@__extendProperties(defaultOptionsCopy, _.clone(options.config)))

    # last check if the route object has config.handler method assigned
    if not (typeof routeObject.config.handler is 'function')
      # if not, throw an error
      throw new Error "The 'config.handler' attribute of route should be a function."

    # return extended/overwritten route object
    routeObject

  # validate if array of fields passed to the request include timestampAttributes and if they are not allowed
  # reply 400 bad request with appropriate message
  # @param [Array] fields array of fields passed as query params
  _validateReturningFields: (fields, reply) ->
    returningArray = _.clone fields
    if not @config.allowTimestampAttributes
      returningArray = _.difference(fields, _.keys(@config.model::timestampAttributes))
    return returningArray

  # GET - return single instance of Model
  # @param [Boolean] ifSerialize boolean which defines if result should be serialized
  # @param [Object] serializer serializer's Class to be used on the instance
  # @param [Object] options additional options which will extend/overwrite current route object
  get: (ifSerialize, serializer, options) =>
    if options? and not (_.isObject options)
      throw new Error "'options' parameter of routing method should be an object"

    options ?= { config: {} }

    routeObject =
      method: 'GET'
      path: "/#{@config.model.metadata.tableName}/{#{@config.model.metadata.primaryKey}}"

      config:
        description: "Return #{@config.model.metadata.model} with specified id"
        tags: @config.tags
        id: "return#{@config.model.metadata.model}"

        validate:
          params:
            "#{@config.model.metadata.primaryKey}": @config.model::attributes[@config.model.metadata.primaryKey].attributes.schema.required()
          query:
            fields: Joi.array().items(Joi.string()).single()

        plugins:
          'hapi-swagger':
            responses:
              '200':
                'description': 'Success'
                'schema': Joi.object(@config.model.getSchema()).label(@config.model.metadata.model)
              '400':
                'description': 'Bad request'
              '401':
                'description': 'Unauthorized'
              '404':
                'description': 'Not found'

        handler: (request, reply) =>
          returning = if request.query.fields? then @_validateReturningFields(request.query.fields) else undefined

          @config.model.objects().getById({ pk: request.params.id, returning: returning }).then (result) =>
            # if query returned any result and the 'ifSerialize' is set to true
            # use Serializer to return results
            if result? and ifSerialize
              serializerClass = if serializer then serializer else @config.serializer
              if not serializerClass?
                throw new Error "There is no serializer specified for #{@constructor.name}"

              serializerInstance = new serializerClass data: result
              serializerInstance.getData().then (serializerData) ->
                reply serializerData
            # otherwise if result was returned and 'ifSerialize' is false, simply return result
            else if result? and not ifSerialize
              reply result
            # if there is no result, return 404 not found error
            else if not result?
              reply Boom.notFound(@config.errorMessages['notFound'] or "#{@config.model.metadata.model} does not exist")

          .catch (error) ->
            reply Boom.badRequest error

    if options? and _.isObject(options)
      @_extendRouteObject routeObject, options

    routeObject

  # GET - return all instances of current Model
  # @param [Boolean] ifSerialize boolean which defines if result should be serialized
  # @param [Object] serializer serializer's Class to be used on the instances
  # @param [Object] options additional options which will extend/overwrite current route object
  list: (ifSerialize, serializer, options) =>
    if options? and not (_.isObject options)
      throw new Error "'options' parameter of routing method should be an object"

    options ?= { config: {} }

    routeObject =
      method: 'GET'
      path: "/#{@config.model.metadata.tableName}"

      config:
        description: "Return all #{@config.pluralName}"
        tags: @config.tags
        id: "returnAll#{@config.pluralName}"

        validate:
          query:
            fields: Joi.array().items(Joi.string()).single()
            orderBy: Joi.string()
            limit: Joi.number().integer().positive()
            page: Joi.number().integer().positive()

        plugins:
          'hapi-swagger':
            responses:
              '200':
                'description': 'Success'
                'schema': Joi.object({ items: Joi.array().items(@config.model.getSchema()) }).label(@config.pluralName)
              '400':
                'description': 'Bad request'
              '401':
                'description': 'Unauthorized'

        handler: (request, reply) =>
          returning = if request.query.fields? then @_validateReturningFields(request.query.fields) else undefined

          # if query params include both 'limit' and 'page', then we use 'filterPaged' DAO operation
          if request.query.limit? and request.query.page?
            daoOperation = @config.model.objects().filterPaged({
                returning: returning
                orderBy: request.query.orderBy
                limit: request.query.limit
                page: request.query.page
              })
          # otherwise we simply perform 'all()'
          else
            daoOperation = @config.model.objects().all({ returning: returning })

          daoOperation.then (objects) =>
            if ifSerialize
              serializerClass = if serializer then serializer else @config.serializer
              if not serializerClass?
                throw new Error "There is no serializer specified for #{@constructor.name}"

              serializerInstance = new serializerClass data: objects, many: true
              serializerInstance.getData().then (serializerData) ->
                reply serializerData
            else if not ifSerialize
              reply objects
          .catch (error) ->
            reply Boom.badRequest error

    if options? and _.isObject(options)
      @_extendRouteObject routeObject, options

    routeObject

  # POST - create new instance of current Model
  # @param [Boolean] ifSerialize boolean which defines if result should be serialized
  # @param [Object] serializer serializer's Class to be used on created instance
  # @param [Object] options additional options which will extend/overwrite current route object
  create: (ifSerialize, serializer, options) =>
    if options? and not (_.isObject options)
      throw new Error "'options' parameter of routing method should be an object"

    options ?= { config: {} }

    routeObject =
      method: 'POST'
      path: "/#{@config.model.metadata.tableName}"

      config:
        description: "Create new #{@config.model.metadata.model}"
        tags: @config.tags
        id: "addNew#{@config.model.metadata.model}"

        validate:
          payload: @config.model.getSchema()

        plugins:
          'hapi-swagger':
            responses:
              '201':
                'description': 'Created'
                'schema': Joi.object(@config.model.getSchema()).label(@config.model.metadata.model)
              '400':
                'description': 'Bad request/validation error'
              '401':
                'description': 'Unauthorized'

        handler: (request, reply) =>
          if request.auth.credentials?
            _.extend request.payload, { whoCreated: request.auth.credentials.user.id }

          @config.model.objects().create({ data: request.payload }).then (result) =>
            if @config.mongoConf? and @config.mongoConf.mongoInstance?

              insertData = {
                model: @config.model.metadata.model
                module: @config.mongoConf.module || 'undefined'
                whoPerformed: if request.auth.credentials? then request.auth.credentials.user else 'undefined'
                action: 'create'
                payload: request.payload
                actionDate: new Date()
                userAgent: request.orig.headers['user-agent']
              }

              currentModelCollection = @config.mongoConf.mongoInstance.db().collection(@config.model.metadata.collectionName)
              currentModelCollection.insert insertData, (error, value) =>
                if error and @config.model.objects().errorLogger?
                  @config.model.objects().errorLogger.error error

            if ifSerialize
              serializerClass = if serializer then serializer else @config.serializer
              if not serializerClass?
                throw new Error "There is no serializer specified for #{@constructor.name}"

              serializerInstance = new serializerClass data: result
              serializerInstance.getData().then (serializerData) ->
                reply(serializerData).code(201)
            else
              # publishObj =
              #   action: 'add'
              #   obj: result
              # @server.publish "/#{@config.model.metadata.tableName}", publishObj
              reply(result).code(201)
          .catch (error) =>
            if error.error is 'ValidationError'
              return reply(error.fields).code(400)

            reply Boom.badRequest(error)

    if options? and _.isObject(options)
      @_extendRouteObject routeObject, options

    routeObject

  # PUT - update specified instance of current Model
  # @param [Boolean] ifSerialize boolean which defines if result should be serialized
  # @param [Object] serializer serializer's Class to be used on updated instance
  # @param [Object] options additional options which will extend/overwrite current route object
  update: (ifSerialize, serializer, options) =>
    if options? and not (_.isObject options)
      throw new Error "'options' parameter of routing method should be an object"

    options ?= { config: {} }

    routeObject =
      method: 'PUT'
      path: "/#{@config.model.metadata.tableName}/{#{@config.model.metadata.primaryKey}}"

      config:
        description: "Update #{@config.model.metadata.model} with specified id"
        tags: @config.tags
        id: "update#{@config.model.metadata.model}"

        validate:
          params:
            "#{@config.model.metadata.primaryKey}": @config.model::attributes[@config.model.metadata.primaryKey].attributes.schema.required()
          payload: @config.model.getSchema()

        plugins:
          'hapi-swagger':
            responses:
              '200':
                'description': 'Updated'
                'schema': Joi.object(@config.model.getSchema()).label(@config.model.metadata.model)
              '400':
                'description': 'Bad request/validation error'
              '401':
                'description': 'Unauthorized'
              '404':
                'description': 'Not found'

        handler: (request, reply) =>
          @config.model.objects().getById({ pk: request.params.id }).then (instance) =>
            if instance?
              previousData = instance.toJSON { attributes: @config.model::fields }

              instance.set request.payload
              instance.save().then (result) =>

                if @config.mongoConf? and @config.mongoConf.mongoInstance?
                  insertData = {
                    model: @config.model.metadata.model
                    module: @config.mongoConf.module || 'undefined'
                    whoPerformed: if request.auth.credentials? then request.auth.credentials.user else 'undefined'
                    action: if request.route.method is 'put' then 'update' else 'partialUpdate'
                    payload: request.payload
                    previousData: previousData
                    actionDate: new Date().addHours(2)
                    userAgent: request.orig.headers['user-agent']
                  }

                  currentModelCollection = @config.mongoConf.mongoInstance.db().collection(@config.model.metadata.collectionName)
                  currentModelCollection.insert insertData, (error, value) =>
                    if error and @config.model.objects().config.errorLogger?
                      @config.model.objects().config.errorLogger.error error

                if ifSerialize
                  serializerClass = if serializer then serializer else @config.serializer
                  if not serializerClass?
                    throw new Error "There is no serializer specified for #{@constructor.name}"

                  serializerInstance = new serializerClass data: result
                  serializerInstance.getData().then (serializerData) ->
                    reply serializerData
                else
                  reply result
              .catch (error) =>
                # if the error from DAO is of ValidationError class, then we simply return fields attribute of error
                if error.error is 'ValidationError'
                  return reply(error.fields).code(400)

                return reply(Boom.badRequest(error))
            else
              return reply Boom.notFound @config.errorMessages.notFound || "#{@config.model.metadata.model} does not exist"

    if options? and _.isObject(options)
      @_extendRouteObject routeObject, options

    routeObject

  # PATCH - perform partial update of specified instance of current Model
  # @param [Boolean] ifSerialize boolean which defines if result should be serialized
  # @param [Object] serializer serializer's Class to be used on updated instance
  # @param [Object] options additional options which will extend/overwrite current route object
  partialUpdate: (ifSerialize, serializer, options) =>
    routeObject = @update ifSerialize, serializer, options

    # it is necessary to change method to PATCH and both description and id of this route method
    # to prevent situation in which it overlaps with '.update()' method
    routeObject.method = 'PATCH'
    routeObject.config.description = "Partial update of #{@config.model.metadata.model}"
    routeObject.config.id = "partialUpdate#{@config.model.metadata.model}"

    # we set the 'partial' parameter of 'getSchema()' method to true
    # in order to return the schema without 'required' attribute for required fields
    # because PATCH allows to update only part of object (model's instance)
    routeObject.config.validate.payload = @config.model.getSchema(undefined, true)

    routeObject

  # DELETE - delete specified instance of current Model, returns 1 if DELETE was successfull
  # @param [Object] options additional options which will extend/overwrite current route object
  delete: (options) =>
    if options? and not (_.isObject options)
      throw new Error "'options' parameter of routing method should be an object"

    options ?= { config: {} }

    routeObject =
      method: 'DELETE'
      path: "/#{@config.model.metadata.tableName}/{#{@config.model.metadata.primaryKey}}"

      config:
        description: "Delete #{@config.model.metadata.model} with specified id"
        tags: @config.tags
        id: "delete#{@config.model.metadata.model}"

        validate:
          params:
            "#{@config.model.metadata.primaryKey}": @config.model::attributes[@config.model.metadata.primaryKey].attributes.schema.required()

        plugins:
          'hapi-swagger':
            responses:
              '200':
                'description': 'Deleted'
              '400':
                'description': 'Bad request'
              '401':
                'description': 'Unauthorized'
              '404':
                'description': 'Not found'

        handler: (request, reply) =>
          whoDeleted = if request.auth.credentials? then request.auth.credentials.user.id else undefined

          @config.model.objects().delete(request.params.id, whoDeleted).then (result) =>
            if result is 1
              if @config.mongoConf? and @config.mongoConf.mongoInstance?

                deleteDataSpecifics = {}
                deleteDataSpecifics[@config.model.metadata.primaryKey] = request.params.id

                deleteData = {
                  model: @config.model.metadata.model
                  module: @config.mongoConf.module || 'undefined'
                  whoPerformed: if request.auth.credentials? then request.auth.credentials.user else 'undefined'
                  action: 'delete'
                  payload: request.params
                  actionDate: new Date().addHours(2)
                  userAgent: request.orig.headers['user-agent']
                }

                currentModelCollection = @config.mongoConf.mongoInstance.db().collection(@config.model.metadata.collectionName)
                currentModelCollection.insert deleteData, (error, value) =>
                  if error and @config.model.objects().config.errorLogger?
                    @config.model.objects().config.errorLogger.error error

              publishObj =
                action: 'delete'
                id: request.params.id
              @server.publish "/#{@config.model.metadata.tableName}", publishObj
              return reply result
            return reply Boom.notFound @config.errorMessages.notFound || "#{@config.model.metadata.model} does not exist!"
          .catch (error) =>
            reply Boom.badRequest error

    if options? and _.isObject(options)
      @_extendRouteObject routeObject, options

    routeObject


module.exports = ModelView
