const test = require('node:test');
const assert = require('node:assert/strict');
const { usernameValid, emailValid, passwordValid, codeDigest } = require('../src/server');

test('username policy accepts safe identifiers only', () => {
  assert.equal(usernameValid('spider_user-1'), true);
  assert.equal(usernameValid('ab'), false);
  assert.equal(usernameValid('not valid'), false);
  assert.equal(usernameValid('a'.repeat(33)), false);
});

test('email validation rejects malformed and oversized values', () => {
  assert.equal(emailValid('person@gmail.com'), true);
  assert.equal(emailValid('not-an-email'), false);
  assert.equal(emailValid('x'.repeat(255)), false);
});

test('password policy requires length, mixed case and a digit', () => {
  assert.equal(passwordValid('SpiderSecure9!'), true);
  assert.equal(passwordValid('short9A'), false);
  assert.equal(passwordValid('alllowercase123'), false);
});

test('verification code digest is bound to challenge identifier', () => {
  process.env.CODE_PEPPER = 'x'.repeat(40);
  assert.notEqual(codeDigest('challenge-a', '123456'), codeDigest('challenge-b', '123456'));
  assert.notEqual(codeDigest('challenge-a', '123456'), codeDigest('challenge-a', '654321'));
});
