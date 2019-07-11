#!/usr/bin/env node
'use strict';

const puppeteer = require('puppeteer');

const createPdf = async() => {
  let browser;
  let exitCode = 0;
  try {
    browser = await puppeteer.launch({args: ['--no-sandbox', '--disable-setuid-sandbox', '--headless']});
    const page = await browser.newPage();
    await page.goto(process.argv[2], {waitUntil: 'networkidle2'});
    await page.pdf({
      path: process.argv[3],
      format: 'A4'
    });
    await page.close();
  } catch (err) {
      console.error(err.message);
      exitCode = 1
  } finally {
    if (browser) {
      await browser.close();
    }
    process.exit(exitCode);
  }
};
createPdf();
