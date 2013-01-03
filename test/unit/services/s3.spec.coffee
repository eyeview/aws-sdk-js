# Copyright 2012-2013 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You
# may not use this file except in compliance with the License. A copy of
# the License is located at
#
#     http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is
# distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
# ANY KIND, either express or implied. See the License for the specific
# language governing permissions and limitations under the License.

AWS = require('../../../lib/core')
helpers = require('../../helpers')

require('../../../lib/services/s3')

describe 'AWS.S3.Client', ->

  s3 = null
  request = (operation, params) ->
    req = new AWS.AWSRequest(s3, operation, params || {})
    req.client.addAllRequestListeners(req)
    req

  beforeEach ->
    s3 = new AWS.S3.Client()

  describe 'dnsCompatibleBucketName', ->

    it 'must be at least 3 characters', ->
      expect(s3.dnsCompatibleBucketName('aa')).toBe(false)

    it 'must not be longer than 63 characters', ->
      b = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      expect(s3.dnsCompatibleBucketName(b)).toBe(false)

    it 'must start with a lower-cased letter or number', ->
      expect(s3.dnsCompatibleBucketName('Abc')).toBe(false)
      expect(s3.dnsCompatibleBucketName('-bc')).toBe(false)
      expect(s3.dnsCompatibleBucketName('abc')).toBe(true)

    it 'must end with a lower-cased letter or number', ->
      expect(s3.dnsCompatibleBucketName('abC')).toBe(false)
      expect(s3.dnsCompatibleBucketName('ab-')).toBe(false)
      expect(s3.dnsCompatibleBucketName('abc')).toBe(true)

    it 'may not contain multiple contiguous dots', ->
      expect(s3.dnsCompatibleBucketName('abc.123')).toBe(true)
      expect(s3.dnsCompatibleBucketName('abc..123')).toBe(false)

    it 'may only contain letters numbers and dots', ->
      expect(s3.dnsCompatibleBucketName('abc123')).toBe(true)
      expect(s3.dnsCompatibleBucketName('abc_123')).toBe(false)

    it 'must not look like an ip address', ->
      expect(s3.dnsCompatibleBucketName('1.2.3.4')).toBe(false)
      expect(s3.dnsCompatibleBucketName('a.b.c.d')).toBe(true)

  describe 'endpoint', ->

    it 'sets hostname to s3.amazonaws.com when region is un-specified', ->
      s3 = new AWS.S3.Client()
      expect(s3.endpoint.hostname).toEqual('s3.amazonaws.com')

    it 'sets hostname to s3.amazonaws.com when region is us-east-1', ->
      s3 = new AWS.S3.Client({ region: 'us-east-1' })
      expect(s3.endpoint.hostname).toEqual('s3.amazonaws.com')

    it 'sets region to us-east-1 when unspecified', ->
      s3 = new AWS.S3.Client({ region: 'us-east-1' })
      expect(s3.config.region).toEqual('us-east-1')

    it 'combines the region with s3 in the endpoint using a - instead of .', ->
      s3 = new AWS.S3.Client({ region: 'us-west-1' })
      expect(s3.endpoint.hostname).toEqual('s3-us-west-1.amazonaws.com')

  describe 'building a request', ->
    build = (operation, params) ->
      req = request(operation, params)
      resp = new AWS.AWSResponse(req)
      req.emitEvents(resp, 'build')
      return resp.httpRequest

    it 'obeys the configuration for s3ForcePathStyle', ->
      config = new AWS.Config({s3ForcePathStyle: true })
      s3 = new AWS.S3.Client(config)
      expect(s3.config.s3ForcePathStyle).toEqual(true)
      req = build('headObject', {Bucket:'bucket', Key:'key'})
      expect(req.endpoint.hostname).toEqual('s3.amazonaws.com')
      expect(req.path).toEqual('/bucket/key')

    describe 'uri escaped params', ->
      it 'uri-escapes path and querystring params', ->
        # bucket param ends up as part of the hostname
        params = { Bucket: 'bucket', Key: 'a b c', VersionId: 'a&b' }
        req = build('headObject', params)
        expect(req.path).toEqual('/a%20b%20c?versionId=a%26b')

      it 'does not uri-escape forward slashes in the path', ->
        params = { Bucket: 'bucket', Key: 'k e/y' }
        req = build('headObject', params)
        expect(req.path).toEqual('/k%20e/y')

      it 'ensures a single forward slash exists', ->
        req = build('listObjects', { Bucket: 'bucket' })
        expect(req.path).toEqual('/')

        req = build('listObjects', { Bucket: 'bucket', MaxKeys:123 })
        expect(req.path).toEqual('/?max-keys=123')

      it 'ensures a single forward slash exists when querystring is present'

    describe 'vitual-hosted vs path-style bucket requests', ->

      describe 'HTTPS', ->

        beforeEach ->
          s3 = new AWS.S3.Client({ sslEnabled: true, region: 'us-east-1' })

        it 'puts dns-compat bucket names in the hostname', ->
          req = build('headObject', {Bucket:'bucket-name',Key:'abc'})
          expect(req.method).toEqual('HEAD')
          expect(req.endpoint.hostname).toEqual('bucket-name.s3.amazonaws.com')
          expect(req.path).toEqual('/abc')

        it 'ensures the path contains / at a minimum when moving bucket', ->
          req = build('listObjects', {Bucket:'bucket-name'})
          expect(req.endpoint.hostname).toEqual('bucket-name.s3.amazonaws.com')
          expect(req.path).toEqual('/')

        it 'puts dns-compat bucket names in path if they contain a dot', ->
          req = build('listObjects', {Bucket:'bucket.name'})
          expect(req.endpoint.hostname).toEqual('s3.amazonaws.com')
          expect(req.path).toEqual('/bucket.name')

        it 'puts dns-compat bucket names in path if configured to do so', ->
          s3 = new AWS.S3.Client({ sslEnabled: true, s3ForcePathStyle: true })
          req = build('listObjects', {Bucket:'bucket-name'})
          expect(req.endpoint.hostname).toEqual('s3.amazonaws.com')
          expect(req.path).toEqual('/bucket-name')

        it 'puts dns-incompat bucket names in path', ->
          req = build('listObjects', {Bucket:'bucket_name'})
          expect(req.endpoint.hostname).toEqual('s3.amazonaws.com')
          expect(req.path).toEqual('/bucket_name')

      describe 'HTTP', ->

        beforeEach ->
          s3 = new AWS.S3.Client({ sslEnabled: false, region: 'us-east-1' })

        it 'puts dns-compat bucket names in the hostname', ->
          req = build('listObjects', {Bucket:'bucket-name'})
          expect(req.endpoint.hostname).toEqual('bucket-name.s3.amazonaws.com')
          expect(req.path).toEqual('/')

        it 'puts dns-compat bucket names in the hostname if they contain a dot', ->
          req = build('listObjects', {Bucket:'bucket.name'})
          expect(req.endpoint.hostname).toEqual('bucket.name.s3.amazonaws.com')
          expect(req.path).toEqual('/')

        it 'puts dns-incompat bucket names in path', ->
          req = build('listObjects', {Bucket:'bucket_name'})
          expect(req.endpoint.hostname).toEqual('s3.amazonaws.com')
          expect(req.path).toEqual('/bucket_name')

  # S3.Client returns a handful of errors without xml bodies (to match the
  # http spec) these tests ensure we give meaningful codes/messages for these.
  describe 'errors with no XML body', ->

    extractError = (statusCode) ->
      req = request('operation')
      resp = new AWS.AWSResponse(req)
      resp.httpResponse.body = ''
      resp.httpResponse.statusCode = statusCode
      req.emit('foo')
      req.emit('extractError', resp, req)
      resp.error

    it 'handles 304 errors', ->
      error = extractError(304)
      expect(error.code).toEqual('NotModified')
      expect(error.message).toEqual(null)

    it 'handles 403 errors', ->
      error = extractError(403)
      expect(error.code).toEqual('Forbidden')
      expect(error.message).toEqual(null)

    it 'handles 404 errors', ->
      error = extractError(404)
      expect(error.code).toEqual('NotFound')
      expect(error.message).toEqual(null)

    it 'misc errors not known to return an empty body', ->
      error = extractError(412) # made up
      expect(error.code).toEqual(412)
      expect(error.message).toEqual(null)

  # tests from this point on are "special cases" for specific aws operations

  describe 'completeMultipartUpload', ->

    it 'returns data when the resp is 200 with valid response', ->
      headers =
        'x-amz-id-2': 'Uuag1LuByRx9e6j5Onimru9pO4ZVKnJ2Qz7/C1NPcfTWAtRPfTaOFg=='
        'x-amz-request-id': '656c76696e6727732072657175657374'
      body =
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <CompleteMultipartUploadResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
          <Location>http://Example-Bucket.s3.amazonaws.com/Example-Object</Location>
          <Bucket>Example-Bucket</Bucket>
          <Key>Example-Object</Key>
          <ETag>"3858f62230ac3c915f300c664312c11f-9"</ETag>
        </CompleteMultipartUploadResult>
        """

      helpers.mockHttpResponse 200, headers, body
      s3.completeMultipartUpload (error, data) ->
        expect(error).toBe(null)
        expect(data).toEqual({
          Location: 'http://Example-Bucket.s3.amazonaws.com/Example-Object'
          Bucket: 'Example-Bucket'
          Key: 'Example-Object'
          ETag: '"3858f62230ac3c915f300c664312c11f-9"'
          RequestId: '656c76696e6727732072657175657374'
        })

    it 'returns an error when the resp is 200 with an error xml document', ->
      body =
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <Error>
        <Code>InternalError</Code>
        <Message>We encountered an internal error. Please try again.</Message>
        <RequestId>656c76696e6727732072657175657374</RequestId>
        <HostId>Uuag1LuByRx9e6j5Onimru9pO4ZVKnJ2Qz7/C1NPcfTWAtRPfTaOFg==</HostId>
      </Error>
      """

      helpers.mockHttpResponse 200, {}, body
      s3.completeMultipartUpload (error, data) ->
        expect(error instanceof Error).toBeTruthy()
        expect(error.code).toEqual('InternalError')
        expect(error.message).toEqual('We encountered an internal error. Please try again.')
        expect(error.statusCode).toEqual(200)
        expect(error.retryable).toEqual(true)
        expect(data).toEqual(null)

  describe 'getBucketLocation', ->

    it 'returns null for the location constraint when not present', ->
      body = '<?xml version="1.0" encoding="UTF-8"?>\n<LocationConstraint xmlns="http://s3.amazonaws.com/doc/2006-03-01/"/>'
      helpers.mockHttpResponse 200, {}, body
      s3.getBucketLocation (error, data) ->
        expect(error).toBe(null)
        expect(data).toEqual({})

    it 'parses the location constraint from the root xml', ->
      headers = { 'x-amz-request-id': 'abcxyz' }
      body = '<?xml version="1.0" encoding="UTF-8"?>\n<LocationConstraint xmlns="http://s3.amazonaws.com/doc/2006-03-01/">EU</LocationConstraint>'
      helpers.mockHttpResponse 200, headers, body
      s3.getBucketLocation (error, data) ->
        expect(error).toBe(null)
        expect(data).toEqual({
          LocationConstraint: 'EU',
          RequestId: 'abcxyz',
        })

  describe 'createBucket', ->
    it 'auto-populates the LocationConstraint based on the region', ->
      loc = null
      s3 = new AWS.S3.Client(region:'eu-west-1')
      s3.makeRequest = (op, params) ->
        loc = params.LocationConstraint
      s3.createBucket(Bucket:'name')
      expect(loc).toEqual('eu-west-1')
