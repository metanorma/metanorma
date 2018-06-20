#!/usr/bin/env node
'use strict';

const puppeteer = require('puppeteer');

const createPdf = async() => {
  let browser;
  try {
    browser = await puppeteer.launch({args: ['--no-sandbox', '--disable-setuid-sandbox']});
    const page = await browser.newPage();
    await page.goto(process.argv[2], {waitUntil: 'networkidle2'});
    await page.pdf({
      path: process.argv[3],
      format: 'A4'
    });
  } catch (err) {
      console.log(err.message);
  } finally {
    if (browser) {
      browser.close();
    }
    process.exit();
  }
};
createPdf();
