/**
 * Component for Twilio Video local views.
 *
 * Authors:
 *   Jonathan Chang <slycoder@gmail.com>
 */

import { requireNativeComponent, View } from 'react-native'
import PropTypes from 'prop-types'
import React from 'react'

const propTypes = {
  ...View.propTypes,
  applyZOrder: PropTypes.bool
}

class TwilioVideoPreview extends React.Component {
  render () {
    return <NativeTwilioVideoPreview {...this.props} />
  }
}

TwilioVideoPreview.propTypes = propTypes

const NativeTwilioVideoPreview = requireNativeComponent(
  'RNTwilioVideoPreview',
  TwilioVideoPreview
)

module.exports = TwilioVideoPreview
