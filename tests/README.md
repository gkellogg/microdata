This README is for the W3C Web Platform Working Group's Microdata test suite.
This test suite contains 2 kinds of tests:

* Microdata to JSON Test (`mdt:MicrodataToJSONTest`) - the result of processing
  a Microdata to JSON.

* CSV to RDFa Test (`mdt:MicrodataToRdfaTest`) - the result of processing
  a Microdata to RDFa.

The manifest.csv file in this directory lists all of the tests in the
CSV WG's test suite. Each test is one of the above tests. All
tests have a name (`mf:name`) and an input (`mf:action`). Evaluation
tests have an expected result (`mf:result`).

* An implementation passes  test if it parses the input
  into a form which can be directly compared with the expected result.

The home of the test suite is <https://w3c.github.io/microdata/tests/>.
The base IRI for parsing each file is `mf:action`.  For example, the test test001j and
test001r require relative IRI resolution against a base of
<https://w3c.github.io/microdata/test001.csv>.
