#!/usr/bin/env node
'use strict';

const puppeteer = require('puppeteer');

const args = () => {
  let args = ['--no-sandbox', '--disable-setuid-sandbox', '--headless'];
  if (!process.platform.startsWith('win')) {
    args << '--single-process';
  }
  return {args};
}

const createPdf = async() => {
  let browser;
  let exitCode = 0;
  try {
    browser = await puppeteer.launch(args());
    const page = await browser.newPage();
    await page.goto(process.argv[2], {
      waitUntil: 'networkidle0',
      timeout: 120000 //ms
    });
    await page.pdf({
      path: process.argv[3],
      format: 'A4'
    });
  } catch (err) {
    console.error(err.message);
    console.error(err.stack);
    exitCode = 1;
  } finally {
    if (browser) {
      browser.close();
    }
    process.exit(exitCode);
  }
};
createPdf();
