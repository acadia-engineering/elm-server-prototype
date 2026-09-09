// Adapted from https://github.com/driverdan/node-XMLHttpRequest
// MIT License, Dan DeFelippi <dan@driverdan.com>

import http from 'node:http';
import https from 'node:https';
import node_url from 'node:url';
import fs from 'node:fs';


global.XMLHttpRequest = class XMLHttpRequest {
  #method = '';
  #headers = { 'user-agent': 'elm-simple-server', 'accept': '*/*', 'transfer-encoding': 'chunked' };
  responseURL = '';
  responseType = '';
  withCredentials = false;
  timeout = 0;

  onload = () => {};
  onerror = () => {};
  ontimeout = () => {};

  #request = { abort: () => {} };
  #response = { headers: {} };
  #aborted = false;

  #responseChunks = [];
  status = null;
  statusText = null;
  response = null;

  open(method, url, async) {
    if (!async) {
      throw new Error('Synchronous XMLHttpRequest not allowed.');
    }
    this.#method = method;
    this.responseURL = url.toString();
  }

  setRequestHeader(hdr, value) {
    hdr = hdr.toLowerCase();
    this.#headers[hdr] = this.#headers[hdr] ? this.#headers[hdr] + ', ' + value : value;
  }

  getAllResponseHeaders() {
    return Object.entries(this.#response.headers)
      .filter(([k,v]) => k !== 'set-cookie' && k !== 'set-cookie2')
      .map(([k,v]) => k + ': ' + v)
      .join('\r\n');
  }

  addEventListener(event, callback) {
    switch (event) {
      case 'load': this.onload = callback; break;
      case 'error': this.onerror = callback; break;
      case 'timeout': this.ontimeout = callback; break;
    }
  }

  abort() {
    this.#aborted = true;
    this.#request.abort();
  }

  send(data) {
    this.responseURL.startsWith('https://')
      ? this.sendHttp(https, 443, data)
      :
    this.responseURL.startsWith('file:///')
      ? this.sendFile(method, this.responseURL.slice(8))
      : this.sendHttp(http, 80, data);
  }

  sendHttp(protocol, defaultPort, data)
  {
    this.#request = protocol.request(this.responseURL, {
      method: this.#method,
      headers: this.#headers,
      timeout: this.timeout,
      withCredentials: this.withCredentials,
      agent: false
    });
    this.#request.on('response', (res) => {
      if (this.#isRedirect(res.statusCode)) {
        return this.#redirect();
      }
      this.#response = res;
      this.status = res.statusCode;
      this.statusText = res.statusMessage;
      res.on('data', (chunk) => { this.#responseChunks.push(chunk); });
      res.on('end', () => {
        if (this.#aborted) return;
        this.response =
          this.responseType == 'arraybuffer'
            ? this.#concat(this.#responseChunks)
            : this.#responseChunks.concat();
        this.onload();
      });
      res.on('error', (err) => { this.#error(err); });
    });
    this.#request.on('error', (err) => { this.#error(err); });
    this.#request.end(ArrayBuffer.isView(data) ? Buffer.from(data.buffer) : data);
  }

  sendFile(method, path) {
    if (method !== 'GET') {
      throw new Error('only GET is supported for file://');
    }

    fs.readFile(path, this.responseType === 'arraybuffer' ? null : 'utf8', (err, data) => {
      if (err) {
        this.#error(err);
      } else {
        this.status = 200;
        this.statusText = 'OK';
        this.response = this.responseType === 'arraybuffer' ? data.buffer : data;
        this.onload();
      }
    });
  }

  #isRedirect(code) {
    return code === 301 || code === 302 || code === 303 || code === 307;
  }

  #redirect(res, data) {
    this.responseURL = res.headers.location;
    if (res.statusCode === 303) this.#method = 'GET';
    this.send(data);
  }

  #concat(chunks) {
    if (chunks.length == 1) return chunks[0].buffer;

    const buffer = new ArrayBuffer(chunks.reduce((len, chunk) => len + chunk.byteLength, 0));
    var offset = 0;
    for (const chunk in chunks)
    {
      buffer.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return buffer;
  }

  #error(err) {
    this.status = 0;
    this.statusText = err;
    this.response = err.stack;
    this.onerror();
  }
};
